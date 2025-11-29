`timescale 1ns/1ps
import interp_pkg::*;

// Top simplificado del proyecto con soporte para stepping funcional.
// Se instancia el controller, las dos RAM (entrada/salida) y se expone
// la señal allow_tick para ser controlada por JTAG/UART o testbench.

module Proyecto2Arqui2 #(
    parameter int LANES  = 4,
    parameter int FRAC   = FRAC_BITS,
    parameter int IMG_W  = 512,
    parameter int IMG_H  = 512,
    parameter int ADDR_W = 19
)(
    input  logic clk,
    input  logic rst_n,

    // Control de operación
    input  logic start,        // inicio de procesamiento
    input  logic allow_tick,   // stepping funcional: 1 = permite avanzar un ciclo

    output logic done          // fin de procesamiento
);

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

