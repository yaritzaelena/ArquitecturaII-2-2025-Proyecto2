transcript on
if {[file exists rtl_work]} {
    vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

# === Compilar todos los módulos necesarios ===

vlog -sv -work work +incdir+C:/intelFPGA_lite/18.1/Proyecto2ArquiGithub/ArquitecturaII-2-2025-Proyecto2 \
  C:/intelFPGA_lite/18.1/Proyecto2ArquiGithub/ArquitecturaII-2-2025-Proyecto2/interp_pkg.sv

vlog -sv -work work +incdir+C:/intelFPGA_lite/18.1/Proyecto2ArquiGithub/ArquitecturaII-2-2025-Proyecto2 \
  C:/intelFPGA_lite/18.1/Proyecto2ArquiGithub/ArquitecturaII-2-2025-Proyecto2/ram_img.sv

vlog -sv -work work +incdir+C:/intelFPGA_lite/18.1/Proyecto2ArquiGithub/ArquitecturaII-2-2025-Proyecto2 \
  C:/intelFPGA_lite/18.1/Proyecto2ArquiGithub/ArquitecturaII-2-2025-Proyecto2/interp_secuencial.sv

vlog -sv -work work +incdir+C:/intelFPGA_lite/18.1/Proyecto2ArquiGithub/ArquitecturaII-2-2025-Proyecto2 \
  C:/intelFPGA_lite/18.1/Proyecto2ArquiGithub/ArquitecturaII-2-2025-Proyecto2/interp_simd4.sv

vlog -sv -work work +incdir+C:/intelFPGA_lite/18.1/Proyecto2ArquiGithub/ArquitecturaII-2-2025-Proyecto2 \
  C:/intelFPGA_lite/18.1/Proyecto2ArquiGithub/ArquitecturaII-2-2025-Proyecto2/controller.sv

# (Opcional, si quieres también el top del proyecto)
vlog -sv -work work +incdir+C:/intelFPGA_lite/18.1/Proyecto2ArquiGithub/ArquitecturaII-2-2025-Proyecto2 \
  C:/intelFPGA_lite/18.1/Proyecto2ArquiGithub/ArquitecturaII-2-2025-Proyecto2/Proyecto2Arqui2.sv

# Testbench del controller
vlog -sv -work work +incdir+C:/intelFPGA_lite/18.1/Proyecto2ArquiGithub/ArquitecturaII-2-2025-Proyecto2 \
  C:/intelFPGA_lite/18.1/Proyecto2ArquiGithub/ArquitecturaII-2-2025-Proyecto2/controller_tb.sv

# === Simulación ===
vsim -t 1ps -L altera_ver -L lpm_ver -L sgate_ver -L altera_mf_ver -L altera_lnsim_ver -L cyclonev_ver -L cyclonev_hssi_ver -L cyclonev_pcie_hip_ver -L rtl_work -L work -voptargs="+acc" controller_tb

add wave *
view structure
view signals
run -all

