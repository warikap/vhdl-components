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

FPGA_PROJECT ?= test
FPGA_PART ?= xc7k325tffv676-2
SRC_FILES ?=
SIM_FILES ?=
XDC_FILES ?=
IP_TCL_FILES ?=
SIM_TIME ?= 1ms

ifneq ($(GUI),)
SIM_MODE = gui
else
SIM_MODE = batch
endif

all: vivado

vivado: $(FPGA_PROJECT)/$(FPGA_PROJECT).xpr
	vivado -nojournal -nolog $<

$(FPGA_PROJECT)/$(FPGA_PROJECT).xpr: Makefile
	echo "create_project -force -part $(FPGA_PART) $@" > create_project.tcl
	echo "set_property target_language VHDL [current_project]" >> create_project.tcl
	for x in $(SRC_FILES); do \
		echo "add_file -fileset sources_1 $$x" >> create_project.tcl; \
		echo "set_property file_type {VHDL 2008} [get_files $$x]" >> create_project.tcl; \
		echo "set_property library work [get_files $$x]" >> create_project.tcl; \
	done
	for x in $(SIM_FILES); do \
		echo "add_file -fileset sim_1 $$x" >> create_project.tcl; \
		echo "set_property file_type {VHDL 2008} [get_files $$x]" >> create_project.tcl; \
		echo "set_property library work [get_files $$x]" >> create_project.tcl; \
	done
	for x in $(XDC_FILES); do echo "add_file -fileset constrs_1 $$x" >> create_project.tcl; done
	for x in $(IP_TCL_FILES); do echo "source $$x" >> create_project.tcl; done
	echo "update_compile_order -fileset sources_1" >> create_project.tcl
	echo "update_compile_order -fileset sim_1" >> create_project.tcl
	echo "set_property -name {xsim.simulate.runtime} -value {$(SIM_TIME)} -objects [get_filesets sim_1]" >> run_simulation.tcl
	echo "exit" >> create_project.tcl
	vivado -nojournal -nolog -mode batch -source create_project.tcl

simulate: $(FPGA_PROJECT)/$(FPGA_PROJECT).xpr
	echo "open_project $<" > run_simulation.tcl
	echo "set_property -name {xsim.simulate.runtime} -value {$(SIM_TIME)} -objects [get_filesets sim_1]" >> run_simulation.tcl
	echo "launch_simulation" >> run_simulation.tcl
	vivado -nojournal -nolog -mode $(SIM_MODE) -source run_simulation.tcl

.PHONY clean:
clean:
	rm -rf $(FPGA_PROJECT)
	rm -rf .Xil *.log *.jou *.cache *.gen *.hw *.ip_user_files *.runs *.sim *.srcs
	rm -rf create_project.tcl run_simulation.tcl
