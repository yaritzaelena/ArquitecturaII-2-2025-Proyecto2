// interp_secuencial.sv
// Núcleo de interpolación bilineal secuencial (1 píxel por operación)

`timescale 1ns/1ps

import interp_pkg::*;

module interp_secuencial #(
  parameter int FRAC = FRAC_BITS
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic        valid_in,

  // 4 píxeles vecinos (escala de grises, 8 bits)
  input  u8_t         p00,
  input  u8_t         p10,
  input  u8_t         p01,
  input  u8_t         p11,

  // fracciones fx, fy en Q0.FRAC (por ejemplo 0..255)
  input  logic [FRAC-1:0] fx,
  input  logic [FRAC-1:0] fy,

  output logic        valid_out,
  output u8_t         pixel_out
);

  // ==========================
  // Cálculo combinacional
  // ==========================

  // Extendemos a 1 bit más para poder representar "1.0 = 256"
  localparam int ONE_LOCAL = 1 << FRAC;

  logic [FRAC:0] fx_ext, fy_ext;
  logic [FRAC:0] wx0, wx1, wy0, wy1;

  // Pesos intermedios (producto de wx*wy)
  logic [2*FRAC+1:0] mult00, mult10, mult01, mult11;
  logic [FRAC:0]      w00, w10, w01, w11;   // tras el >> FRAC

  // Productos peso * píxel
  logic [31:0] term00, term10, term01, term11;
  logic [31:0] sum_q;
  integer      sum_int;

  // Extensión de fx, fy
  assign fx_ext = {1'b0, fx};  // 0.xxx
  assign fy_ext = {1'b0, fy};

  // wx1 = fx, wx0 = 1 - fx
  assign wx1 = fx_ext;
  assign wy1 = fy_ext;
  assign wx0 = ONE_LOCAL - fx_ext; // 1 - fx
  assign wy0 = ONE_LOCAL - fy_ext; // 1 - fy

  // Productos de pesos (Q0.FRAC * Q0.FRAC = Q0.(2*FRAC))
  assign mult00 = wx0 * wy0;
  assign mult10 = wx1 * wy0;
  assign mult01 = wx0 * wy1;
  assign mult11 = wx1 * wy1;

  // Volvemos a Q0.FRAC (desplazando a la derecha FRAC bits)
  assign w00 = mult00 >> FRAC; // sigue representando un peso 0..1
  assign w10 = mult10 >> FRAC;
  assign w01 = mult01 >> FRAC;
  assign w11 = mult11 >> FRAC;

  // Cada término: píxel (8 bits) * peso (~9 bits) => ~17 bits, usamos 32 por comodidad
  always_comb begin
    term00 = p00 * w00;
    term10 = p10 * w10;
    term01 = p01 * w01;
    term11 = p11 * w11;

    // Suma total sigue en Q8.8 (FRAC bits de fracción)
    sum_q = term00 + term10 + term01 + term11;

    // Volvemos a entero: >> FRAC
    sum_int = sum_q >>> FRAC;

    // Clamp a [0,255]
  end

  u8_t pixel_comb;
  always_comb begin
    pixel_comb = clamp_u8(sum_int);
  end

  // ==========================
  // Registro de salida (1 ciclo de latencia)
  // ==========================

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_out <= 1'b0;
      pixel_out <= '0;
    end else begin
      valid_out <= valid_in;
      if (valid_in) begin
        pixel_out <= pixel_comb;
      end
    end
  end

endmodule
