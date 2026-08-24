# MIPI-CSI2-RX

This repository contains the Verilog source code for a MIPI CSI-2 Receiver (RX) design, focusing on ECC (Error Correction Code) and CRC (Cyclic Redundancy Check) modules.

## Files Included

* `2ff_sync.v` - 2-stage flip-flop synchronizer.
* `D_flipflop.v` - Basic D-type flip-flop.
* `asyncc_fifo.v` - Asynchronous FIFO.
* `axis_asyncc_fifo.v` - AXI-Stream compatible asynchronous FIFO.
* `crc.v` - Cyclic Redundancy Check module.
* `csi2_ecc_rx.v` - MIPI CSI-2 Error Correction Code Receiver.
* `csi2_rx_ecc_crc.v` - Top-level module integrating ECC and CRC for MIPI CSI-2 RX.
* `pixel_unpack.v` - Pixel unpacking logic.
* `rd_ptr_hdlr.v` - Read pointer handler for FIFOs.
* `sync_fifo.v` - Synchronous FIFO.
* `tb_csi2_rx_ecc_crc.v` - Testbench for the CSI-2 RX ECC/CRC module.
* `w_ptr_handler.v` - Write pointer handler for FIFOs.

## Overview

A hardware implementation for parsing MIPI CSI-2 data streams, verifying packet integrity with ECC and CRC checks, and handling pixel data unpacking.

## Project Structure

Note: Dumping all files into the root directory isn't a scalable practice for larger projects. Consider organizing these into `src/` and `tb/` (testbench) directories in the future.
