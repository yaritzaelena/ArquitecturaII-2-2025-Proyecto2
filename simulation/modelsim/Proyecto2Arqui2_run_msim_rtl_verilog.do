transcript on
if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vlog -sv -work work +incdir+C:/Users/irodr/Documents/ArquitecturaII-2-2025-Proyecto2 {C:/Users/irodr/Documents/ArquitecturaII-2-2025-Proyecto2/interp_pkg.sv}
vlog -sv -work work +incdir+C:/Users/irodr/Documents/ArquitecturaII-2-2025-Proyecto2 {C:/Users/irodr/Documents/ArquitecturaII-2-2025-Proyecto2/ram_img.sv}
vlog -sv -work work +incdir+C:/Users/irodr/Documents/ArquitecturaII-2-2025-Proyecto2 {C:/Users/irodr/Documents/ArquitecturaII-2-2025-Proyecto2/step_controller.sv}
vlog -sv -work work +incdir+C:/Users/irodr/Documents/ArquitecturaII-2-2025-Proyecto2 {C:/Users/irodr/Documents/ArquitecturaII-2-2025-Proyecto2/interp_secuencial.sv}
vlog -sv -work work +incdir+C:/Users/irodr/Documents/ArquitecturaII-2-2025-Proyecto2 {C:/Users/irodr/Documents/ArquitecturaII-2-2025-Proyecto2/Proyecto2Arqui2.sv}
vlog -sv -work work +incdir+C:/Users/irodr/Documents/ArquitecturaII-2-2025-Proyecto2 {C:/Users/irodr/Documents/ArquitecturaII-2-2025-Proyecto2/interp_simd4.sv}
vlog -sv -work work +incdir+C:/Users/irodr/Documents/ArquitecturaII-2-2025-Proyecto2 {C:/Users/irodr/Documents/ArquitecturaII-2-2025-Proyecto2/controller_downscale_seq.sv}
vlog -sv -work work +incdir+C:/Users/irodr/Documents/ArquitecturaII-2-2025-Proyecto2 {C:/Users/irodr/Documents/ArquitecturaII-2-2025-Proyecto2/controller_downscale_simd4.sv}
vlog -sv -work work +incdir+C:/Users/irodr/Documents/ArquitecturaII-2-2025-Proyecto2 {C:/Users/irodr/Documents/ArquitecturaII-2-2025-Proyecto2/controller_downscale.sv}

