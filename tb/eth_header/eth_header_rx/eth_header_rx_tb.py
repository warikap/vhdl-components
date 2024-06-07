#!/usr/bin/env python
"""
Copyright (c) 2020 Alex Forencich
Copyright (c) 2023 Marcin Zaremba

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

from scapy.layers.l2 import Ether

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotb.regression import TestFactory

from cocotbext.axi import AxiStreamBus, AxiStreamSource, AxiStreamSink
from cocotbext.axi.stream import define_stream

EthHdrBus, EthHdrTransaction, EthHdrSource, EthHdrSink, EthHdrMonitor = define_stream("EthHdr",
    signals=["hdr_valid", "hdr_ready", "dst_mac", "src_mac", "type"]
)


class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.aclk, 8, units="ns").start())

        self.source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.aclk, dut.aresetn,
                                      reset_active_level=False)

        self.header_sink = EthHdrSink(EthHdrBus.from_prefix(dut, "m_eth"), dut.aclk, dut.aresetn,
                                      reset_active_level=False)
        self.payload_sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_eth_payload_axis"), dut.aclk,
                                          dut.aresetn, reset_active_level=False)

    def set_idle_generator(self, generator=None):
        if generator:
            self.source.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.header_sink.set_pause_generator(generator())
            self.payload_sink.set_pause_generator(generator())

    async def reset(self):
        self.dut.aresetn.value = 0
        for _ in range(5):
            await RisingEdge(self.dut.aclk)
        self.dut.aresetn.value = 1
        await RisingEdge(self.dut.aclk)
        await RisingEdge(self.dut.aclk)

    async def send(self, pkt):
        await self.source.send(bytes(pkt))

    async def recv(self):
        rx_header = await self.header_sink.recv()
        rx_payload = await self.payload_sink.recv()

        assert not rx_payload.tuser

        eth = Ether()
        eth.dst = rx_header.dst_mac.integer.to_bytes(6, 'big')
        eth.src = rx_header.src_mac.integer.to_bytes(6, 'big')
        eth.type = rx_header.type.integer
        rx_pkt = eth / bytes(rx_payload.tdata)

        return Ether(bytes(rx_pkt))


async def run_test(dut, payload_lengths=None, payload_data=None, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    await tb.reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    test_pkts = []

    for payload in [payload_data(x) for x in payload_lengths()]:
        eth = Ether(src='5A:51:52:53:54:55', dst='DA:D1:D2:D3:D4:D5', type=0x8000)
        test_pkt = eth / payload

        test_pkts.append(test_pkt.copy())

        await tb.send(test_pkt)

    for test_pkt in test_pkts:
        rx_pkt = await tb.recv()

        tb.log.info("RX packet: %s", repr(rx_pkt))

        assert bytes(rx_pkt) == bytes(test_pkt)

    assert tb.header_sink.empty()
    assert tb.payload_sink.empty()

    await RisingEdge(dut.aclk)
    await RisingEdge(dut.aclk)


def cycle_pause():
    return itertools.cycle([1, 1, 1, 0])


def size_list():
    return list(range(1, 128)) + [512, 1500, 9200] + [60-14]*10


def incrementing_payload(length):
    return bytes(itertools.islice(itertools.cycle(range(256)), length))


if cocotb.SIM_NAME:

    factory = TestFactory(run_test)
    factory.add_option("payload_lengths", [size_list])
    factory.add_option("payload_data", [incrementing_payload])
    factory.add_option("idle_inserter", [None, cycle_pause])
    factory.add_option("backpressure_inserter", [None, cycle_pause])
    factory.generate_tests()
