# Copyright (c) 2023 Marcin Zaremba
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

TOPLEVEL_LANG = vhdl

SIM ?= ghdl
WAVES ?= 1

COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

DUT      = axis_gmii
TOPLEVEL = $(DUT)
MODULE   = $(DUT)_tb
VHDL_SOURCES += ../../../src/$(DUT).vhd
VHDL_SOURCES += ../../../src/$(DUT)_rx.vhd
VHDL_SOURCES += ../../../src/$(DUT)_tx.vhd
SIM_BUILD = work

ifeq ($(SIM), questa)

#VHDL_GPI_INTERFACE = vhpi
COMPILE_ARGS += -2008

else ifeq ($(SIM), ghdl)

COMPILE_ARGS += --std=08
GHDL_ARGS += --std=08
SIM_ARGS += --wave=${MODULE}.ghw

endif

include $(shell cocotb-config --makefiles)/Makefile.sim

clean::
	rm -rf __pycache__

STYLE_FILES = $(VHDL_SOURCES)
include ../../../../common/style.mk
