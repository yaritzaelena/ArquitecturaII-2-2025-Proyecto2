`timescale 1ns/1ps
import interp_pkg::*;

// Top del proyecto con soporte para stepping funcional.
// Se instancian:
//   - step_controller  : genera allow_tick según cmd_step/cmd_continue/cmd_halt
//   - controller       : controla RAM de entrada/salida + SIMD4
//   - ram_img (in/out) : memorias internas (imagen origen / imagen destino)
//
// Para la FPGA, puedes mapear:
//   clk         -> CLOCK_50
//   rst_n       -> KEY[0] (activo en 0)
//   start       -> pulsador / bit desde JTAG
//   cmd_*       -> bits desde JTAG o switches
//   done/ halted-> LEDs

module Proyecto2Arqui2 #(
    parameter int LANES  = 4,
    parameter int FRAC   = FRAC_BITS,
    parameter int IMG_W  = 512,
    parameter int IMG_H  = 512,
    parameter int ADDR_W = 19
)(
    // Reloj y reset global
    input  logic clk,
    input  logic rst_n,

    // Control de operación
    input  logic start,         // pulso de inicio de procesamiento

    // Comandos de stepping (desde PC/JTAG/switches)
    input  logic cmd_step,      // un ciclo de avance
    input  logic cmd_continue,  // ejecución continua
    input  logic cmd_halt,      // pausa en stepping

    // Estado hacia el exterior
    output logic done,          // fin de procesamiento
    output logic halted         // indica si estamos detenidos (stepping)
);

    // --------------------------------------------------
    // Señal interna allow_tick (enable de un ciclo)
    // --------------------------------------------------
    logic allow_tick;

    // --------------------------------------------------
    // Señales entre controller y RAMs
    // --------------------------------------------------
    logic              in_we;
    logic [ADDR_W-1:0] in_addr;
    logic [7:0]        in_wdata;
    logic [7:0]        in_rdata;

    logic              out_we;
    logic [ADDR_W-1:0] out_addr;
    logic [7:0]        out_wdata;
    logic [7:0]        out_rdata;

    // --------------------------------------------------
    // Instancia de step_controller
    // --------------------------------------------------
    step_controller u_step_ctrl (
        .clk         (clk),
        .rst_n       (rst_n),

        .cmd_step    (cmd_step),
        .cmd_continue(cmd_continue),
        .cmd_halt    (cmd_halt),

        .allow_tick  (allow_tick),
        .halted      (halted)
    );

    // --------------------------------------------------
    // RAM de entrada (imagen original)
    // --------------------------------------------------
    ram_img #(
        .ADDR_WIDTH(ADDR_W),
        .DATA_WIDTH(8)
    ) ram_in (
        .clk   (clk),
        .we    (in_we),
        .addr  (in_addr),
        .wdata (in_wdata),
        .rdata (in_rdata)
    );

    // --------------------------------------------------
    // RAM de salida (imagen escalada / resultado)
    // --------------------------------------------------
    ram_img #(
        .ADDR_WIDTH(ADDR_W),
        .DATA_WIDTH(8)
    ) ram_out (
        .clk   (clk),
        .we    (out_we),
        .addr  (out_addr),
        .wdata (out_wdata),
        .rdata (out_rdata)
    );

    // --------------------------------------------------
    // Controlador SIMD + stepping funcional
    // --------------------------------------------------
    controller #(
        .LANES (LANES),
        .FRAC  (FRAC),
        .IMG_W (IMG_W),
        .IMG_H (IMG_H),
        .ADDR_W(ADDR_W)
    ) u_ctrl (
        .clk       (clk),
        .rst_n     (rst_n),

        // stepping: solo avanza cuando allow_tick = 1
        .allow_tick(allow_tick),

        .start     (start),
        .done      (done),

        .in_we     (in_we),
        .in_addr   (in_addr),
        .in_wdata  (in_wdata),
        .in_rdata  (in_rdata),

        .out_we    (out_we),
        .out_addr  (out_addr),
        .out_wdata (out_wdata)
    );

endmodule


