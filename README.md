```text
[2025-08-25 15:33:01 UTC] xrun -Q -unbuffered '-timescale' '1ns/1ns' '-sysv' '-access' '+rw' design.sv testbench.sv  
TOOL:	xrun	23.09-s001: Started on Aug 25, 2025 at 11:33:02 EDT
xrun: 23.09-s001: (c) Copyright 1995-2023 Cadence Design Systems, Inc.
	Top level design units:
		tb_axi4_lite_slave
Loading snapshot worklib.tb_axi4_lite_slave:sv .................... Done
xcelium> source /xcelium23.09/tools/xcelium/files/xmsimrc
xcelium> run
[0] Reset asserted
[45000] Reset deasserted
[95000] WRITE  addr=0x00000014 data=0xdeadbeef strb=0xf -> BRESP=0
[125000] READ   addr=0x00000014 -> RDATA=0xdeadbeef RRESP=0
Transaction 1 PASSED: Full write/read OK
[175000] WRITE  addr=0x00000018 data=0xcafebabe strb=0x3 -> BRESP=0
[205000] READ   addr=0x00000018 -> RDATA=0x0000babe RRESP=0
Transaction 2 PASSED: Partial write OK
[255000] WRITE  addr=0x0000001c data=0x11223344 strb=0x0 -> BRESP=2
[285000] READ   addr=0x0000001c -> RDATA=0x00000000 RRESP=0
Transaction 3 PASSED: Zero-strobe OK
[335000] WRITE  addr=0x0000000d data=0xa5a5a5a5 strb=0xf -> BRESP=2
[365000] READ   addr=0x0000000d -> RDATA=0x00000000 RRESP=2
Transaction 4 PASSED: Unaligned address SLVERR OK
[415000] WRITE  addr=0x00000080 data=0x5555aaaa strb=0xf -> BRESP=0
[445000] READ   addr=0x00000080 -> RDATA=0x5555aaaa RRESP=0
Transaction 5 PASSED: Out-of-range SLVERR OK
[545000] WRITE  addr=0x00000020 data=0x0badf00d strb=0xf -> BRESP=0
Transaction 6 PASSED: AW first, delayed W OK
[665000] WRITE  addr=0x00000024 data=0xfeedc0de strb=0xf -> BRESP=0
Transaction 7 PASSED: W first, delayed AW OK
[695000] READ   addr=0x00000020 -> RDATA=0x0badf00d RRESP=0
Transaction 8 PASSED: Read-back reg 8 OK
[725000] READ   addr=0x00000024 -> RDATA=0xfeedc0de RRESP=0
Transaction 9 PASSED: Read-back reg 9 OK
[735000] *** ALL TESTS PASSED ***
Simulation complete via $finish(1) at time 735 NS + 0
./testbench.sv:250         $finish;
xcelium> exit
TOOL:	xrun	23.09-s001: Exiting on Aug 25, 2025 at 11:33:03 EDT  (total: 00:00:01)
Finding VCD file...
./waveform.vcd
[2025-08-25 15:33:03 UTC] Opening EPWave...
Done
