// interp_simd4.sv
// Procesa 4 píxeles por ciclo usando 4 núcleos secuenciales en paralelo

`timescale 1ns/1ps
import interp_pkg::*;

module interp_simd4 #(
    parameter int LANES = 4,
    parameter int FRAC  = FRAC_BITS
)(
    input  logic             clk,
    input  logic             rst_n,

    input  logic             valid_in,

    // Entradas vectoriales
    input  u8_t              p00_vec [LANES],
    input  u8_t              p10_vec [LANES],
    input  u8_t              p01_vec [LANES],
    input  u8_t              p11_vec [LANES],
    input  logic [FRAC-1:0]  fx_vec  [LANES],
    input  logic [FRAC-1:0]  fy_vec  [LANES],

    // Salidas
    output logic             valid_out,
    output u8_t              pixel_out_vec [LANES]
);

    // Señales internas por lane
    logic valid_out_lane[LANES];

    // ==========================
    // 4 instancias del núcleo secuencial
    // ==========================

    genvar i;
    generate
        for (i = 0; i < LANES; i++) begin : SIMD_LANE

            interp_secuencial core_i (
                .clk        (clk),
                .rst_n      (rst_n),
                .valid_in   (valid_in),

                .p00        (p00_vec[i]),
                .p10        (p10_vec[i]),
                .p01        (p01_vec[i]),
                .p11        (p11_vec[i]),
                .fx         (fx_vec[i]),
                .fy         (fy_vec[i]),

                .valid_out  (valid_out_lane[i]),
                .pixel_out  (pixel_out_vec[i])
            );

        end
    endgenerate

    // ==========================
    // valid_out común
    // ==========================

    // Todos los lanes tienen la MISMA latencia,
    // así que cualquier valid_out_lane sirve.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            valid_out <= 1'b0;
        else
            valid_out <= valid_in;  // Latencia fija = 1 ciclo
    end

endmodule
