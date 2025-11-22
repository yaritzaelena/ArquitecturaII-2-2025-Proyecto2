module bilinear_core_scalar #(
    parameter int PIXEL_W = 8,             // bits por píxel
    parameter int FRAC_W  = 8,             // bits fraccionales (Q8.8)
    parameter int COEFF_W = 16,            // ancho total de coeficiente
    parameter int ACC_W   = PIXEL_W + COEFF_W + 2
)(
    input  logic clk,
    input  logic rst,

    input  logic [PIXEL_W-1:0] p00,
    input  logic [PIXEL_W-1:0] p01,
    input  logic [PIXEL_W-1:0] p10,
    input  logic [PIXEL_W-1:0] p11,

    input  logic [COEFF_W-1:0] w00,
    input  logic [COEFF_W-1:0] w01,
    input  logic [COEFF_W-1:0] w10,
    input  logic [COEFF_W-1:0] w11,

    output logic [PIXEL_W-1:0] out_pix
);

    logic [ACC_W-1:0] acc;
    logic [ACC_W-1:0] m00, m01, m10, m11;
    logic [ACC_W-1:0] shifted;

    always_comb begin
        // Productos píxel * peso
        m00 = p00 * w00;
        m01 = p01 * w01;
        m10 = p10 * w10;
        m11 = p11 * w11;

        // Suma ponderada
        acc = m00 + m01 + m10 + m11;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            out_pix <= '0;
        end else begin
            // Q8.8 -> desplazar 8 bits fraccionales
            shifted = acc >> FRAC_W;
            out_pix <= shifted[PIXEL_W-1:0];
        end
    end

endmodule

