module simd_top #(
    parameter int N         = 4,
    parameter int PIXEL_W   = 8,
    parameter int FRAC_W    = 8,              // Q8.8
    parameter int COEFF_W   = 16,
    parameter int ACC_W     = PIXEL_W + COEFF_W + 2
)(
    input  logic clk,
    input  logic rst,
    input  logic load,

    // Vecinos de entrada
    input  logic [PIXEL_W-1:0] p00 [N-1:0],
    input  logic [PIXEL_W-1:0] p01 [N-1:0],
    input  logic [PIXEL_W-1:0] p10 [N-1:0],
    input  logic [PIXEL_W-1:0] p11 [N-1:0],

    // Pesos de entrada
    input  logic [COEFF_W-1:0] w00 [N-1:0],
    input  logic [COEFF_W-1:0] w01 [N-1:0],
    input  logic [COEFF_W-1:0] w10 [N-1:0],
    input  logic [COEFF_W-1:0] w11 [N-1:0],

    // Salidas SIMD
    output logic [PIXEL_W-1:0] out_pix [N-1:0]
);

    simd_interpolator #(
        .N       (N),
        .PIXEL_W (PIXEL_W),
        .FRAC_W  (FRAC_W),
        .COEFF_W (COEFF_W),
        .ACC_W   (ACC_W)
    ) simd_unit (
        .clk    (clk),
        .rst    (rst),
        .load   (load),
        .p00_in (p00),
        .p01_in (p01),
        .p10_in (p10),
        .p11_in (p11),
        .w00_in (w00),
        .w01_in (w01),
        .w10_in (w10),
        .w11_in (w11),
        .out_pix(out_pix)
    );

endmodule

