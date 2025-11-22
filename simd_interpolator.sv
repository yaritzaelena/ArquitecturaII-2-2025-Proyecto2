module simd_interpolator #(
    parameter int N         = 4,
    parameter int PIXEL_W   = 8,
    parameter int FRAC_W    = 8,  
    parameter int COEFF_W   = 16,
    parameter int ACC_W     = PIXEL_W + COEFF_W + 2
)(
    input  logic clk,
    input  logic rst,
    input  logic load,

    // Entradas SIMD (usar arreglos UNPACKED válidos en ModelSim)
    input  logic [PIXEL_W-1:0] p00_in [N-1:0],
    input  logic [PIXEL_W-1:0] p01_in [N-1:0],
    input  logic [PIXEL_W-1:0] p10_in [N-1:0],
    input  logic [PIXEL_W-1:0] p11_in [N-1:0],

    input  logic [COEFF_W-1:0] w00_in [N-1:0],
    input  logic [COEFF_W-1:0] w01_in [N-1:0],
    input  logic [COEFF_W-1:0] w10_in [N-1:0],
    input  logic [COEFF_W-1:0] w11_in [N-1:0],

    // Salidas SIMD
    output logic [PIXEL_W-1:0] out_pix [N-1:0]
);

    // Registros SIMD
    logic [PIXEL_W-1:0] p00_reg [N-1:0];
    logic [PIXEL_W-1:0] p01_reg [N-1:0];
    logic [PIXEL_W-1:0] p10_reg [N-1:0];
    logic [PIXEL_W-1:0] p11_reg [N-1:0];

    logic [COEFF_W-1:0] w00_reg [N-1:0];
    logic [COEFF_W-1:0] w01_reg [N-1:0];
    logic [COEFF_W-1:0] w10_reg [N-1:0];
    logic [COEFF_W-1:0] w11_reg [N-1:0];

    integer k;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (k = 0; k < N; k++) begin
                p00_reg[k] <= '0;
                p01_reg[k] <= '0;
                p10_reg[k] <= '0;
                p11_reg[k] <= '0;

                w00_reg[k] <= '0;
                w01_reg[k] <= '0;
                w10_reg[k] <= '0;
                w11_reg[k] <= '0;
            end
        end else if (load) begin
            for (k = 0; k < N; k++) begin
                p00_reg[k] <= p00_in[k];
                p01_reg[k] <= p01_in[k];
                p10_reg[k] <= p10_in[k];
                p11_reg[k] <= p11_in[k];

                w00_reg[k] <= w00_in[k];
                w01_reg[k] <= w01_in[k];
                w10_reg[k] <= w10_in[k];
                w11_reg[k] <= w11_in[k];
            end
        end
    end

    // SIMD LANES
    genvar i;
    generate
        for (i = 0; i < N; i++) begin : GEN_LANES
            bilinear_core_scalar #(
                .PIXEL_W(PIXEL_W),
                .FRAC_W (FRAC_W),
                .COEFF_W(COEFF_W),
                .ACC_W  (ACC_W)
            ) core_lane (
                .clk(clk),
                .rst(rst),
                .p00(p00_reg[i]),
                .p01(p01_reg[i]),
                .p10(p10_reg[i]),
                .p11(p11_reg[i]),
                .w00(w00_reg[i]),
                .w01(w01_reg[i]),
                .w10(w10_reg[i]),
                .w11(w11_reg[i]),
                .out_pix(out_pix[i])
            );
        end
    endgenerate

endmodule

