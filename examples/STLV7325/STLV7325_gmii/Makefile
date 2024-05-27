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


# FPGA settings
FPGA_PROJECT ?= STLV7325_gmii
FPGA_PART ?= xc7k325tffv676-2

# Files for synthesis
SRC_FILES = src/rtl/STLV7325_gmii.vhd
SRC_FILES += ../../../hdl/axis_gmii/axis_gmii_rx.vhd
SRC_FILES += ../../../hdl/axis_gmii/axis_gmii_tx.vhd
SRC_FILES += ../../../hdl/axis_gmii/axis_gmii.vhd

# XDC files
XDC_FILES = src/constr/STLV7325_gmii.xdc

# IP and BD
IP_TCL_FILES = src/ip/gmii_clk.tcl
#IP_TCL_FILES += src/ip/fifo_axis4k.tcl
#IP_TCL_FILES += src/ip/ila_axis8.tcl
IP_TCL_FILES += src/bd/system.tcl

include ../../../common/vivado.mk

STYLE_FILES = $(SRC_FILES)
include ../../../common/style.mk
