// ===============================================================
// controller_downscale.sv
// Wrapper unificado para downscaling con interpolación bilineal
// que permite seleccionar entre:
//
//   - Modo SECUENCIAL: controller_downscale_seq
//   - Modo SIMD (4 lanes): controller_downscale_simd4
//
// Selección mediante mode_simd:
//   0 -> secuencial
//   1 -> SIMD
//
// El wrapper:
//   - Entrega la misma interfaz hacia el top (RAM, start, done, counters)
//   - Usa allow_tick dividido para congelar el modo no seleccionado
//   - Multiplexa las señales de RAM y los contadores
//
// Nota: la escala se sigue fijando con SCALE_NUM/SCALE_DEN (parámetros).
// Más adelante se puede pasar a registros configurables vía JTAG.
// ===============================================================

`timescale 1ns/1ps
import interp_pkg::*;

module controller_downscale #(
    parameter int FRAC       = FRAC_BITS,
    parameter int IMG_W      = 512,
    parameter int IMG_H      = 512,
    parameter int ADDR_W     = 19,
    parameter int LANES      = 4,

    parameter int SCALE_NUM  = 1,  // numerador factor escala
    parameter int SCALE_DEN  = 1   // denominador factor escala
)(
    input  logic              clk,
    input  logic              rst_n,

    // Stepping global desde step_controller
    input  logic              allow_tick,

    // Control de operación
    input  logic              start,
    input  logic              mode_simd,   // 0 = secuencial, 1 = SIMD

    output logic              done,

    // RAM de entrada
    output logic              in_we,
    output logic [ADDR_W-1:0] in_addr,
    output logic [7:0]        in_wdata,
    input  logic [7:0]        in_rdata,

    // RAM de salida
    output logic              out_we,
    output logic [ADDR_W-1:0] out_addr,
    output logic [7:0]        out_wdata,

    // Performance counters (del modo activo)
    output logic [31:0]       cycle_count,
    output logic [31:0]       rd_count,
    output logic [31:0]       wr_count
);

    // ===========================================================
    // Señales internas para cada controlador
    // ===========================================================
    // allow_tick separados para congelar el modo no seleccionado
    logic allow_tick_seq;
    logic allow_tick_simd;

    assign allow_tick_seq  = allow_tick & ~mode_simd;
    assign allow_tick_simd = allow_tick &  mode_simd;

    // Señales SEQ
    logic              in_we_seq;
    logic [ADDR_W-1:0] in_addr_seq;
    logic [7:0]        in_wdata_seq;
    logic              out_we_seq;
    logic [ADDR_W-1:0] out_addr_seq;
    logic [7:0]        out_wdata_seq;
    logic              done_seq;
    logic [31:0]       cycles_seq, rd_seq, wr_seq;

    // Señales SIMD
    logic              in_we_simd;
    logic [ADDR_W-1:0] in_addr_simd;
    logic [7:0]        in_wdata_simd;
    logic              out_we_simd;
    logic [ADDR_W-1:0] out_addr_simd;
    logic [7:0]        out_wdata_simd;
    logic              done_simd;
    logic [31:0]       cycles_simd, rd_simd, wr_simd;

    // ===========================================================
    // Instancia del controlador SECUENCIAL
    // ===========================================================
    controller_downscale_seq #(
        .FRAC      (FRAC),
        .IMG_W     (IMG_W),
        .IMG_H     (IMG_H),
        .ADDR_W    (ADDR_W)
    ) u_seq (
        .clk         (clk),
        .rst_n       (rst_n),
        .allow_tick  (allow_tick_seq),
        .start       (start),
        .done        (done_seq),

        .in_we       (in_we_seq),
        .in_addr     (in_addr_seq),
        .in_wdata    (in_wdata_seq),
        .in_rdata    (in_rdata),

        .out_we      (out_we_seq),
        .out_addr    (out_addr_seq),
        .out_wdata   (out_wdata_seq),

        .cycle_count (cycles_seq),
        .rd_count    (rd_seq),
        .wr_count    (wr_seq)
    );

    // ===========================================================
    // Instancia del controlador SIMD
    // ===========================================================
    controller_downscale_simd4 #(
        .FRAC      (FRAC),
        .IMG_W     (IMG_W),
        .IMG_H     (IMG_H),
        .ADDR_W    (ADDR_W),
        .LANES     (LANES),
        .SCALE_NUM (SCALE_NUM),
        .SCALE_DEN (SCALE_DEN)
    ) u_simd (
        .clk         (clk),
        .rst_n       (rst_n),
        .allow_tick  (allow_tick_simd),
        .start       (start),
        .done        (done_simd),

        .in_we       (in_we_simd),
        .in_addr     (in_addr_simd),
        .in_wdata    (in_wdata_simd),
        .in_rdata    (in_rdata),

        .out_we      (out_we_simd),
        .out_addr    (out_addr_simd),
        .out_wdata   (out_wdata_simd),

        .cycle_count (cycles_simd),
        .rd_count    (rd_simd),
        .wr_count    (wr_simd)
    );

    // ===========================================================
    // Multiplexado de salidas según mode_simd
    // ===========================================================
    always_comb begin
        if (mode_simd) begin
            // MODO SIMD
            in_we       = in_we_simd;
            in_addr     = in_addr_simd;
            in_wdata    = in_wdata_simd;

            out_we      = out_we_simd;
            out_addr    = out_addr_simd;
            out_wdata   = out_wdata_simd;

            done        = done_simd;
            cycle_count = cycles_simd;
            rd_count    = rd_simd;
            wr_count    = wr_simd;
        end
        else begin
            // MODO SECUENCIAL
            in_we       = in_we_seq;
            in_addr     = in_addr_seq;
            in_wdata    = in_wdata_seq;

            out_we      = out_we_seq;
            out_addr    = out_addr_seq;
            out_wdata   = out_wdata_seq;

            done        = done_seq;
            cycle_count = cycles_seq;
            rd_count    = rd_seq;
            wr_count    = wr_seq;
        end
    end

endmodule
