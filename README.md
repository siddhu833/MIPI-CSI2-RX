# MIPI CSI-2 RX to AXI4-Stream Bridge

CSI-2 receiver pipeline that streams image data into an AXI-based SoC.
Verified with a Python image loopback (grayscale RAW8).

```
Python (image -> grayscale pixels)                         Python (pixels -> image, compare)
        |                                                                ^
   input.mem                                                        output.mem
        |                                                                |
 [csi2_tx_packer] --CSI-2 bytes--> [csi2_rx_llp] --> [axis_async_fifo] --> AXI4-Stream
  ECC generation                    ECC check/correct   (clk_byte -> clk_axi,   tdata = pixel
  CRC-16 compute                    CRC-16 validate      your asyncc_fifo)      tuser = {line_err, SOF}
  FS / line / FE packets            cut-through                                 tlast = end of line
        clk_byte (100 MHz) -------------------------------->|<----- clk_axi (150 MHz)
```

## Files
| File | Purpose |
|---|---|
| `rtl/csi2_tx_packer.v` | TX packet packer: Frame Start, RAW8 long packets (DI 0x2A) with header ECC + payload CRC-16, Frame End |
| `rtl/csi2_ecc_gen.v`, `rtl/csi2_ecc_rx.v` | Header ECC generator / checker (single-bit correct, multi-bit detect) |
| `rtl/crc16_1021.v` | CRC-16-CCITT (x^16+x^12+x^5+1), seed 0xFFFF |
| `rtl/csi2_rx_llp.v` | RX low-level protocol: header ECC, cut-through payload, on-the-fly CRC check, last byte tagged with CRC result |
| `rtl/axis_async_fifo.v` | AXI4-Stream wrapper around `asyncc_fifo` (CDC), skid buffer for back-pressure |
| `rtl/cdc/*` | Your CDC blocks: `asyncc_fifo`, `sync_2ff`, `D_flipflop`, `w_ptr_handler`, `rd_ptr_hdlr` (unchanged) |
| `rtl/rst_sync.v` | Reset synchronizer (async assert, sync de-assert), one per clock domain |
| `rtl/csi2_rx_axis_bridge.v` | **RX bridge top**: LLP + CDC FIFO + AXI4-Stream + counters + synchronized sticky flags |
| `rtl/csi2_loopback_top.v` | System top: TX packer -> link (with fault-injection mask) -> RX bridge |
| `tb/tb_csi2_loopback.v` | Verilog testbench |
| `scripts/img_to_mem.py`, `scripts/mem_to_img.py` | Python TX data generation / image reconstruction |

## Run
```
python scripts/img_to_mem.py          # image -> sim_data/input.mem (grayscale)
<simulate tb_csi2_loopback>           # writes sim_data/output.mem
python scripts/mem_to_img.py          # rebuild image + pixel-by-pixel compare
```
* **Vivado:** open `vivado/csi2_rx_axis_bridge.xpr` -> Run Behavioral Simulation
  (re-create with `vivado -mode batch -source scripts/create_vivado_project.tcl`)
* **Questa/ModelSim:** from the project root `vsim -do scripts/run_questa.do`

## Results
| Test | Result |
|---|---|
| Frame 1: 899x658 grayscale image (591,542 px), random TREADY back-pressure | 0 pixel errors, SOF/EOL correct, no FIFO overflow |
| Python reconstruction | identical to input |
| Frame 2: 1-bit header error | corrected by ECC, line delivered |
| Frame 2: 2-bit header error | detected by ECC, line dropped |
| Frame 2: payload bit error | detected by CRC, line tagged `tuser[1]` |
| Frame 3: clean frame after errors | received correctly |
| AXI4-Stream TVALID/TDATA stable under back-pressure | 0 violations |
| Synthesis (xc7z020) | 341 LUTs, 384 FFs; timing met at 100 MHz / 150 MHz; Vivado report_cdc: 28/28 crossings safe |

## Clock / reset domains (for CDC tools)
| Domain | Clock | Reset | Logic |
|---|---|---|---|
| byte | `clk_byte` | `rst_n` -> `u_rst_byte` / `u_rst_tx` | TX packer, RX LLP, FIFO write side, counters |
| axi  | `clk_axi`  | `rst_n` -> `u_rst_axi` | FIFO read side, AXI4-Stream output, sticky flags |

Crossings:
1. FIFO write pointer (Gray) byte -> axi : `asyncc_fifo/ff_r` (sync_2ff)
2. FIFO read pointer (Gray) axi -> byte : `asyncc_fifo/ff_w` (sync_2ff)
3. FIFO memory data byte -> axi : qualified by the synchronized pointers (FIFO structure)
4. Sticky error flags (3 single-bit levels) byte -> axi : `u_sts_sync` (sync_2ff)
5. `rst_n` -> each domain : `rst_sync`

## JasperGold lint + CDC (JasperGold 2019.09) - signed off
```
jg -superlint run_lint.tcl     # Superlint  -> lint_report_csi2.txt / .html
jg -cdc       run_cdc.tcl      # CDC + RDC  -> cdc_report_csi2.txt / .html, cdc_open_csi2.txt
```
(`analyze -sv` is required: `-verilog` parses as Verilog-95 and rejects generate/`+:`.)

### Lint
| Finding | Resolution |
|---|---|
| EXP_IS_OVFL `hdr_cnt + 1` (csi2_rx_llp) | fixed: counter set explicitly 1->2->3 |
| BLK_NO_RCHB FSM `default` (csi2_rx_llp) | waived: intentional illegal-state recovery |
Result: 0 open, 1 waived.

### CDC / RDC
| Run | Open | Change |
|---|---|---|
| 1 | 504 (103 CDC + 401 RDC) | - |
| 2 | 72 | CDC blocks converted to async active-low reset (no reset logic inside the synchronizer chain); Gray pointers registered in the source domain (no combinational logic before the synchronizer) |
| 3 | 5 | `asyncc_fifo` declared as a FIFO scheme (`check_cdc -scheme -add fifo`); Gray coding formally proven (`-signal_config -add_gray_code` / `-prove`) |
| 4 | **0** | 5 reviewed waivers (below) |

Formally proven: `g_w_ptr` / `g_rptr` Gray coded, FIFO `no_read_on_empty`, `wptr/rptr_gray_coded`, status-flag synchronizer stability (x3).

Waivers (all in `run_cdc.tcl` with comments):
1. `no_write_on_full` - cut-through RX cannot stall the PHY; writes while full are ignored by the FIFO and reported on `sts_overflow` (system requirement: clk_axi drain rate > link byte rate).
2. `wptr_stable`, 3. `rptr_stable` - Gray pointers (proven): a pointer that changes again before being sampled is still captured as a valid old/new value.
4. convergence at `ovf_flag`, 5. at `u_cdc_fifo.r_en_pipe` - logic using the FIFO full/empty outputs; derived from proven Gray pointers, so conservative.

Other rules: `fifo_detection true`, `ignore_non_resettable_flop true` (FIFO RAM is intentionally not reset).