# About
Module and testbench for filtering bad-formatted packets, in the context of a Hermes NoC.

# Theory of Operation
Invalid packets in a wormhole NoC can make the whole NoC inoperable by unexpectedly consuming network resources.
If no checking is performed, any arbitrary flit can be interpreted by a Router as a header flit, either making a packet be routed towards an unexpected (possibly non-existent) Router or be interpreted by the network as having a different amount of payload flits than expected.
Even worse, excessive delays between flit insertion can cause arbitration logic to be locked to a specific port for an unacceptable amount of time.

This module provides a manner to prevent such packet being injected into the network by performing checking at every flit that is injected on a Router's local port.
Address and Size flits require an 8-bit checksum that performs an "authentication" of sorts, that if valid, identify a flit as being a ADDR or SIZE flit.
Furthermore, after a valid ADDR flit is seen by the filter, each flit after that will be susceptible to a timeout, if they are not injected into the Router within a pre-determined number of clock cycles.

Address checksums are generated from XOR operations between the NoC total size (X size concatenated to Y size) and the XY target of the packet in question
This checksum should be placed at bits [23:16]:
```console
for i from 0 to 7:
  AddrChecksum[i] = NoCSize[2*i] ^ NoCSize[2*i + 1] ^ ADDR[2*i] ^ ADDR[2*i + 1]
```

SIZE checksums are generated from the size of the packet in question and the checksum of the ADDR filt of the packet in question. This checksum should be placed at bits [31:24]:
```console
for i from 0 to 7:
  SizeChecksum[i] = SIZE[3*i] ^ SIZE[3*i + 1] ^ SIZE[3*i + 2] ^ AddrChecksum[i]
```

If both these checksums are valid, the packet is seen as valid and is passed from the filter into the associated Router's local port.

After the ADDR checksum is validated, each flit of the packet being injected into the network must be seen at Filter's external interface in a timely manner, else the packet is dropped, and any remaining payload flits are immediately transmitted as zeroes.
In case the timeout event occurs when expecting a SIZE filt, the ADDR filt is dropped and not passed on to the Router. 
Note that in this case, any flits injected after this will be expected to be a new ADDR flit, and will not be passed on to the Router unless the contain a valid checksum.

# Running simulations
Using Cadence XCelium, simulating the included testbench can be done by executing the following commands:

```console
$ cd sim
$ xrun -f run.f -gui -access rwc -v93
```
This will open the SimVision waveform viewer, where the user can select and see specific signals of the design.
