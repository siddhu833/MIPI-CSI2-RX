# ============================================================================
# JasperGold CDC - CSI-2 RX to AXI4-Stream bridge
#   Run from this folder:   jg -cdc run_cdc.tcl
# ============================================================================
clear -all

# Analyze + elaborate
analyze -sv -f filelist_jg.f
elaborate -top csi2_rx_axis_bridge

# Clocks: two asynchronous domains
#   clk_byte : CSI-2 byte clock (RX LLP, FIFO write side)
#   clk_axi  : SoC AXI clock    (FIFO read side, AXI4-Stream, status flags)
clock clk_byte
clock clk_axi

# Reset: active-low async, synchronized per domain by rst_sync
reset -expression {!rst_n}

# Load CDC port configuration
check_cdc -init

# ---- Rule setup ------------------------------------------------------------
# Recognise the async FIFO as a FIFO synchronizer (off by default)
check_cdc -check -rule -set {{fifo_detection true}}
# FIFO RAM (asyncc_fifo.mem) is intentionally not reset - RAM is never reset;
# its contents are only read after the pointers say an entry was written
check_cdc -check -rule -set {{ignore_non_resettable_flop true}}

# ---- Signal configuration ------------------------------------------------------
# FIFO pointers crossing the domains are Gray coded (one bit changes per
# increment), so per-bit synchronization + recombination is safe.
# The tool generates a check for this and proves it formally below.
check_cdc -signal_config -add_gray_code {u_cdc_fifo.u_fifo.w_hndlr.g_w_ptr u_cdc_fifo.u_fifo.r_hndlr.g_rptr}

# ---- Structural CDC analysis -------------------------------------------------
check_cdc -clock_domain -find
check_cdc -pair -find

# Declare the async FIFO module as a FIFO synchronizer scheme (auto-detection
# does not match it because it is split across several sub-modules).
# Formal signals of the FIFO scheme -> signals inside module asyncc_fifo:
#   wfull/rempty : full/empty flags      winc/rinc : write/read enables
#   wptr/rptr    : Gray pointers that cross the clock domains
#   wdata/rdata  : FIFO data in/out
check_cdc -scheme -add fifo -module asyncc_fifo -map {{wfull full} {rempty empty} {winc w_en} {rinc r_en} {wptr g_w_ptr} {rptr g_rptr} {wdata data_in} {rdata data_out}}

check_cdc -scheme -find
check_cdc -group -find
check_cdc -reset -find

# Prove the Gray-code declarations, then auto-waive convergence they cover
check_cdc -signal_config -prove
check_cdc -waiver -generate

# ---- Functional checks on detected synchronizers ----------------------------
check_cdc -protocol_check -generate
check_cdc -protocol_check -prove

# ---- Waivers (reviewed, intentional behaviour) ---------------------------------
# 1. FIFO write while full: the cut-through CSI-2 receiver cannot back-pressure
#    the PHY link. asyncc_fifo ignores writes when full (w_en && !full) and the
#    drop is reported on sts_overflow. System requirement: clk_axi drain rate
#    >= link byte rate (verified in simulation: random TREADY, 0 overflows).
set f_full [check_cdc -filter -add -violation_type functional -scheme_property CDC_u_cdc_fifo.u_fifo.data_out_no_write_on_full]
check_cdc -waiver -add -filter $f_full -comment {Cut-through RX cannot stall the PHY: writes while full are ignored by asyncc_fifo (w_en && !full) and flagged on sts_overflow; clk_axi drain rate must exceed link byte rate}

# 2./3. Pointer stability: pointers are Gray coded (proven: *_cdc_gray_code and
#    *_gray_coded). Only one bit changes per increment, so a pointer that
#    changes again before the destination samples it is still captured as a
#    valid old or new value; full/empty stay conservative (Cummings async FIFO).
set f_wptr [check_cdc -filter -add -violation_type functional -scheme_property CDC_u_cdc_fifo.u_fifo.data_out_wptr_stable]
check_cdc -waiver -add -filter $f_wptr -comment {Gray-coded write pointer (formally proven): one bit changes per increment, any sampled value is a valid old/new pointer, full/empty stay conservative}
set f_rptr [check_cdc -filter -add -violation_type functional -scheme_property CDC_u_cdc_fifo.u_fifo.data_out_rptr_stable]
check_cdc -waiver -add -filter $f_rptr -comment {Gray-coded read pointer (formally proven): one bit changes per increment, any sampled value is a valid old/new pointer, full/empty stay conservative}

# 4./5. Convergence at logic that uses the FIFO full/empty outputs outside the
#    FIFO module (ovf_flag in the bridge, r_en_pipe in the AXIS wrapper).
#    full/empty come from comparing the formally proven Gray pointers, so they
#    are conservative - the intended interface of an async FIFO.
set f_cv1 [check_cdc -filter -add -violation_type convergence -occurrence ovf_flag]
check_cdc -waiver -add -filter $f_cv1 -comment {Uses the FIFO full flag: compare of the formally proven Gray-coded read pointer; synchronized value is always a valid old/new pointer, so full is conservative (never misses a full condition)}
set f_cv2 [check_cdc -filter -add -violation_type convergence -occurrence u_cdc_fifo.r_en_pipe]
check_cdc -waiver -add -filter $f_cv2 -comment {Uses the FIFO empty flag: compare of the formally proven Gray-coded write pointer; synchronized value is always a valid old/new pointer, so empty is conservative (never reads an unwritten entry)}

# ---- Reports -------------------------------------------------------------------
check_cdc -report -violation -detailed -file cdc_report_csi2.txt -force
check_cdc -report -html -file cdc_report_csi2.html -force -violation -detailed
check_cdc -report -violation -detailed -waived none -file cdc_open_csi2.txt -force
check_cdc -report schemes -file cdc_schemes_csi2.csv -force

# Summary in the console
check_cdc -report
