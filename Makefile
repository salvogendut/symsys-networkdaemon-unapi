ASM ?= rasm
SCC_AS ?= ../scc/bin/as
SCC_LD ?= ../scc/bin/ld
SCC_RELOC ?= ../scc/bin/reloc
WRAPPER := Dmn-Network-\#UNA.asm

.PHONY: all check check-backend check-wrapper check-scc msx-spike msx-symbos stage-msx-symbos run-msx run-msx-symbos clean

all: netd-una-scc.exe

GENERATED := build/Dmn-Network-Head-UNAPI.asm build/Dmn-Network-UNAPI-integrated.asm build/symbos_lib-SystemManager.asm build/symbos_lib-DesktopManager.asm build/symbos_lib-FileManager.asm

netd-una.exe: $(WRAPPER) Dmn-Network-UNAPI.asm $(GENERATED)
	$(ASM) $(WRAPPER) -ob netd-una.exe

$(GENERATED) &: tools/generate_integrated_daemon.py ../symsys-networkdaemon/Dmn-Network-Head.asm ../symsys-networkdaemon/Dmn-Network.asm ../symdoc-developer/symbos_lib-SystemManager.asm ../symdoc-developer/symbos_lib-DesktopManager.asm ../symdoc-developer/symbos_lib-FileManager.asm
	python3 tools/generate_integrated_daemon.py

build/netd-una-scc.s: tools/generate_scc_daemon.py Dmn-Network-UNAPI.asm $(GENERATED)
	python3 tools/generate_scc_daemon.py

build/netd-una-scc.o: build/netd-una-scc.s
	$(SCC_AS) -o build/netd-una-scc.o build/netd-una-scc.s

netd-una-scc.exe: build/netd-una-scc.o
	$(SCC_LD) -o netd-una-scc.exe -R build/netd-una-scc.rel build/netd-una-scc.o
	$(SCC_RELOC) netd-una-scc.exe build/netd-una-scc.rel
	cp netd-una-scc.exe netd-una.exe

build/msx/SYMUNAPI.COM: tools/symunapi_msx.asm
	mkdir -p build/msx
	cd build/msx && rasm ../../tools/symunapi_msx.asm

check:
	$(MAKE) check-backend
	$(MAKE) check-wrapper
	$(MAKE) check-scc

check-backend:
	$(ASM) tests/backend_syntax.asm -ob /tmp/symbos-unapi-backend.bin

check-wrapper: $(GENERATED)
	$(ASM) $(WRAPPER) -ob netd-una.exe

check-scc: netd-una-scc.exe

msx-spike:
	bash tools/build_unapi_spike.sh

msx-symbos: netd-una.exe build/msx/SYMUNAPI.COM
	cp netd-una.exe /var/home/salvogendut/Downloads/MSXSYMBOS/SYMBOS/NETD-UNA.EXE
	cp build/msx/SYMUNAPI.COM /var/home/salvogendut/Downloads/MSXSYMBOS/SYMUNAPI.COM
	bash tools/build_msx_symbos_img.sh

stage-msx-symbos: netd-una-scc.exe build/msx/SYMUNAPI.COM
	mcopy -o -i QA/MSXSYMBOS.IMG@@16384 netd-una.exe ::/SYMBOS/NETD-UNA.EXE
	mcopy -o -i QA/MSXSYMBOS.IMG@@16384 build/msx/SYMUNAPI.COM ::/SYMUNAPI.COM
	mcopy -o -i QA/MSXSYMBOS.IMG@@16384 SYMBOS.BAT ::/SYMBOS.BAT

run-msx:
	bash tools/run_msx.sh

run-msx-symbos:
	bash tools/run_msx.sh QA/MSXSYMBOS.IMG

clean:
	rm -f netd-una.exe netd-una-scc.exe Dmn-Network-\#UNA.bin Dmn-Network-\#UNA.sym Dmn-Network-\#UNA.lst
	rm -rf build QA/UNAPISPK.IMG QA/MSX
