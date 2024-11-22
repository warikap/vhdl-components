#!/usr/bin/env python
"""

Copyright (c) 2020 Alex Forencich
Copyright (c) 2024 Marcin Zaremba

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

"""

import itertools
import logging
import os

import cocotb_test.simulator

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb.regression import TestFactory

from cocotbext.axi import AxiStreamSink, AxiStreamBus
from cocotbext.uart import UartSource


class TB:
    def __init__(self, dut, baud=921600):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.aclk, 10, units="ns").start())

        self.source = UartSource(dut.rxd, baud=baud, bits=len(dut.m_axis_tdata), stop_bits=1)

        self.sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.aclk, dut.aresetn, reset_active_level=False)

        dut.prescale.setimmediatevalue(int(1/10e-9/baud))

    async def reset(self):
        self.dut.aresetn.value = 0
        for _ in range(5):
            await RisingEdge(self.dut.aclk)
        self.dut.aresetn.value = 1
        await RisingEdge(self.dut.aclk)
        await RisingEdge(self.dut.aclk)


async def run_test(dut, payload_lengths=None, payload_data=None):

    tb = TB(dut)

    await tb.reset()

    for test_data in [payload_data(x) for x in payload_lengths()]:

        await tb.source.write(test_data)

        rx_data = bytearray()

        while len(rx_data) < len(test_data):
            rx_data.extend(await tb.sink.read())

        tb.log.info("Read data: %s", rx_data)

        assert tb.sink.empty()

        await Timer(2, 'us')

    await RisingEdge(dut.aclk)
    await RisingEdge(dut.aclk)


def prbs31(state=0x7fffffff):
    while True:
        for i in range(8):
            if bool(state & 0x08000000) ^ bool(state & 0x40000000):
                state = ((state & 0x3fffffff) << 1) | 1
            else:
                state = (state & 0x3fffffff) << 1
        yield state & 0xff


def size_list():
    return list(range(1, 16)) + [128]


def incrementing_payload(length):
    return bytearray(itertools.islice(itertools.cycle(range(256)), length))


def prbs_payload(length):
    gen = prbs31()
    return bytearray([next(gen) for x in range(length)])


if cocotb.SIM_NAME:

    factory = TestFactory(run_test)
    factory.add_option("payload_lengths", [size_list])
    factory.add_option("payload_data", [incrementing_payload, prbs_payload])
    factory.generate_tests()
