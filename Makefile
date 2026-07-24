ASM ?= rasm
SCC_CC ?= ../scc/bin/cc
SCC_AS ?= ../scc/bin/as
SCC_LD ?= ../scc/bin/ld
SCC_RELOC ?= ../scc/bin/reloc
UNAPI_SNAPSHOT_DIR ?= .
WRAPPER := Dmn-Network-\#UNA.asm

.PHONY: all check check-backend check-wrapper check-scc check-settime-qa legacy-symunapi msx-spike msx-symbos stage-msx-symbos stage-settime-qa run-msx run-msx-symbos clean

all: netd-una.exe

GENERATED := build/Dmn-Network-Head-UNAPI.asm build/Dmn-Network-UNAPI-integrated.asm build/symbos_lib-SystemManager.asm build/symbos_lib-DesktopManager.asm build/symbos_lib-FileManager.asm

$(GENERATED) &: tools/generate_integrated_daemon.py ../symsys-networkdaemon/Dmn-Network-Head.asm ../symsys-networkdaemon/Dmn-Network.asm ../symdoc-developer/symbos_lib-SystemManager.asm ../symdoc-developer/symbos_lib-DesktopManager.asm ../symdoc-developer/symbos_lib-FileManager.asm
	python3 tools/generate_integrated_daemon.py

build/netd-una-scc.s: tools/generate_scc_daemon.py Dmn-Network-UNAPI.asm $(GENERATED)
	python3 tools/generate_scc_daemon.py

build/netd-una-scc.o: build/netd-una-scc.s
	$(SCC_AS) -o build/netd-una-scc.o build/netd-una-scc.s

netd-una.exe: build/netd-una-scc.o
	$(SCC_LD) -o netd-una.exe -R build/netd-una-scc.rel build/netd-una-scc.o
	$(SCC_RELOC) netd-una.exe build/netd-una-scc.rel

build/legacy/SYMUNAPI.COM: LEGACY/symunapi_msx.asm
	mkdir -p build/legacy
	cd build/legacy && rasm ../../LEGACY/symunapi_msx.asm

SYMUNAPI.COM: build/legacy/SYMUNAPI.COM
	cp build/legacy/SYMUNAPI.COM SYMUNAPI.COM

legacy-symunapi: SYMUNAPI.COM

build/settime-qa.o: tools/settime_qa_scc.c
	mkdir -p build
	$(SCC_CC) -c tools/settime_qa_scc.c -o build/settime-qa.o

build/msx/SETTIME.COM: build/settime-qa.o
	mkdir -p build/msx
	$(SCC_CC) build/settime-qa.o -lnet -o build/msx/SETTIME.COM

check:
	$(MAKE) check-backend
	$(MAKE) check-wrapper
	$(MAKE) check-scc
	$(MAKE) check-settime-qa

check-backend:
	$(ASM) tests/backend_syntax.asm -ob /tmp/symbos-unapi-backend.bin

check-wrapper: $(GENERATED)
	$(ASM) $(WRAPPER) -ob /tmp/netd-una-wrapper.exe

check-scc: netd-una.exe

check-settime-qa: build/msx/SETTIME.COM

msx-spike:
	bash tools/build_unapi_spike.sh

msx-symbos: netd-una.exe SYMUNAPI.COM AUTOEXEC.BAT
	cp netd-una.exe /var/home/salvogendut/Downloads/MSXSYMBOS/SYMBOS/NETD-UNA.EXE
	UNAPI_SNAPSHOT_DIR=$(UNAPI_SNAPSHOT_DIR) bash tools/build_msx_symbos_img.sh

stage-msx-symbos: netd-una.exe SYMUNAPI.COM AUTOEXEC.BAT
	MTOOLS_SKIP_CHECK=1 mcopy -o -i QA/MSXSYMBOS.IMG@@16384 netd-una.exe ::/SYMBOS/NETD-UNA.EXE
	MTOOLS_SKIP_CHECK=1 mcopy -o -i QA/MSXSYMBOS.IMG@@16384 SYMUNAPI.COM $(UNAPI_SNAPSHOT_DIR)/SYMUNAPI.DAT $(UNAPI_SNAPSHOT_DIR)/SYMUNAPI.SEG ::/SYMBOS/
	MTOOLS_SKIP_CHECK=1 mcopy -o -i QA/MSXSYMBOS.IMG@@16384 AUTOEXEC.BAT ::/AUTOEXEC.BAT

stage-settime-qa: build/msx/SETTIME.COM
	mcopy -o -i QA/MSXSYMBOS.IMG@@16384 build/msx/SETTIME.COM ::/SYMBOS/SETTIME.COM

run-msx:
	bash tools/run_msx.sh

run-msx-symbos:
	bash tools/run_msx.sh QA/MSXSYMBOS.IMG

clean:
	rm -f netd-una.exe Dmn-Network-\#UNA.bin Dmn-Network-\#UNA.sym Dmn-Network-\#UNA.lst
	rm -rf build QA/UNAPISPK.IMG QA/MSX
