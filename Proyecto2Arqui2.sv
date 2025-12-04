`timescale 1ns/1ps
import interp_pkg::*;

module Proyecto2Arqui2 #(
    parameter int LANES      = 4,
    parameter int FRAC       = FRAC_BITS,
    parameter int IMG_W      = 512,
    parameter int IMG_H      = 512,
    parameter int ADDR_W     = 19,

    // Factor de escala global:
    //   escala = SCALE_NUM / SCALE_DEN
    //   Ej: 1/2 = 0.5 (512x512 -> 256x256)
    parameter int SCALE_NUM  = 1,
    parameter int SCALE_DEN  = 2
)(
    // Reloj y reset global
    input  logic clk,
    input  logic rst_n,

    // Control de operación
    input  logic start,         // pulso de inicio de procesamiento

    // Comandos de stepping
    input  logic cmd_step,      // un ciclo de avance
    input  logic cmd_continue,  // ejecución continua
    input  logic cmd_halt,      // pausa en stepping

    // Selección de modo
    input  logic mode_simd,     // 0 = secuencial, 1 = SIMD

    // Estado hacia el exterior
    output logic done,          // fin de procesamiento
    output logic halted         // indica si estamos detenidos (stepping)
);

    // --------------------------------------------------
    // Señal interna allow_tick
    // --------------------------------------------------
    logic allow_tick;

    // --------------------------------------------------
    // Señales entre controller_downscale y RAMs
    // --------------------------------------------------
    logic              in_we;
    logic [ADDR_W-1:0] in_addr;
    logic [7:0]        in_wdata;
    logic [7:0]        in_rdata;

    logic              out_we;
    logic [ADDR_W-1:0] out_addr;
    logic [7:0]        out_wdata;
    logic [7:0]        out_rdata;

    // Performance counters
    logic [31:0] cycle_count_ctrl;
    logic [31:0] rd_count_ctrl;
    logic [31:0] wr_count_ctrl;

    // --------------------------------------------------
    // step_controller
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
    // RAM entrada
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
    // RAM salida
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
    // Controlador unificado SEQ / SIMD
    // --------------------------------------------------
    controller_downscale #(
        .FRAC      (FRAC),
        .IMG_W     (IMG_W),
        .IMG_H     (IMG_H),
        .ADDR_W    (ADDR_W),
        .LANES     (LANES),
        .SCALE_NUM (SCALE_NUM),
        .SCALE_DEN (SCALE_DEN)
    ) u_ctrl (
        .clk         (clk),
        .rst_n       (rst_n),

        .allow_tick  (allow_tick),
        .start       (start),
        .mode_simd   (mode_simd),

        .done        (done),

        .in_we       (in_we),
        .in_addr     (in_addr),
        .in_wdata    (in_wdata),
        .in_rdata    (in_rdata),

        .out_we      (out_we),
        .out_addr    (out_addr),
        .out_wdata   (out_wdata),

        .cycle_count (cycle_count_ctrl),
        .rd_count    (rd_count_ctrl),
        .wr_count    (wr_count_ctrl)
    );

endmodule
