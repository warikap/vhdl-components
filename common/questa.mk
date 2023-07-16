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

SRC_FILES ?=
SIM_FILES ?=
SIM_TOP ?= unknown_tb
WORK_LIB ?= work

ifneq ($(GUI),)
SIM_CMD = vsim -voptargs=+acc $(WORK_LIB).$(SIM_TOP)
else
SIM_CMD = vsim -c -voptargs=+acc $(WORK_LIB).$(SIM_TOP) -do "run -all; exit -f"
endif

.PHONY: sim simclean
sim:
	vlib $(WORK_LIB)
	for x in $(SRC_FILES); do \
		vcom -suppress 1346,1236,1090 -2008 -work $(WORK_LIB) $$x; \
	done
	for x in $(SIM_FILES); do \
		vcom -suppress 1346,1236,1090 -2008 -work $(WORK_LIB) $$x; \
	done
	$(SIM_CMD)

simclean:
	rm -rf $(WORK_LIB)
