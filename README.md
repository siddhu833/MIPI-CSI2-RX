# MIPI-CSI2-RX

This repository contains the Verilog source code for a MIPI CSI-2 Receiver implementation.

## Project Structure
The project contains the following Verilog modules, including but not limited to:
- `csi2_rx_ecc_crc.v`: Top module handling ECC and CRC for the MIPI CSI-2 RX.
- `csi2_ecc_rx.v`: ECC decoder block.
- `crc.v`: CRC calculator block.
- `pixel_unpack.v`: Pixel unpacking module.
- Various FIFO modules (`sync_fifo.v`, `asyncc_fifo.v`, `axis_asyncc_fifo.v`) and utility components.

## Tools
Developed using Xilinx Vivado.

## Author
siddhu833
