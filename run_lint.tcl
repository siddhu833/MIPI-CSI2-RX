clear -all

# Initialize Superlint
check_superlint -init

# Analyze RTL files (compile order in filelist_jg.f)
analyze -sv -f filelist_jg.f

# Elaborate top module (RX bridge, two clock domains)
elaborate -top csi2_rx_axis_bridge

# Define clock/reset environment
clock clk_byte
clock clk_axi
reset -expression {!rst_n}

# Extract lint properties
check_superlint -extract

# Waivers: intentional, unreachable FSM default branches (safety recovery)
set why {Intentional FSM default branch: recovers from an illegal state encoding (e.g. bit upset); unreachable in normal operation by design}
check_superlint -waiver -add -tag BLK_NO_RCHB -source_file rtl/csi2_rx_llp.v -start_line 264 -end_line 264 -comment $why

# Prove all extracted properties
check_superlint -prove

# Generate lint reports (text + HTML)
check_superlint -report -violation -property -detailed -file lint_report_csi2.txt -force
check_superlint -report -violation -property -detailed -file lint_report_csi2.html -force -html

# Summary in the console
check_superlint -report
