# ModelSim / Questa: run from the project root
#   python scripts/img_to_mem.py       (once, creates sim_data/*.mem)
#   vsim -do scripts/run_questa.do
#   python scripts/mem_to_img.py

if {[file exists work]} { vdel -lib work -all }
vlib work

vlog -f filelist.f
vlog tb/tb_csi2_loopback.v

vsim -voptargs=+acc work.tb_csi2_loopback

add wave -divider "Link";   add wave /tb_csi2_loopback/dut/clk_byte /tb_csi2_loopback/dut/tx_byte /tb_csi2_loopback/dut/tx_valid /tb_csi2_loopback/phy_err_mask
add wave -divider "RX LLP"; add wave /tb_csi2_loopback/dut/u_rx/u_rx_llp/state /tb_csi2_loopback/dut/u_rx/rx_data /tb_csi2_loopback/dut/u_rx/rx_valid /tb_csi2_loopback/dut/u_rx/rx_last /tb_csi2_loopback/dut/u_rx/rx_ecc_corrected /tb_csi2_loopback/dut/u_rx/rx_ecc_error /tb_csi2_loopback/dut/u_rx/rx_crc_error
add wave -divider "AXIS";   add wave /tb_csi2_loopback/dut/clk_axi /tb_csi2_loopback/m_tdata /tb_csi2_loopback/m_tvalid /tb_csi2_loopback/m_tready /tb_csi2_loopback/m_tlast /tb_csi2_loopback/m_tuser

run -all
