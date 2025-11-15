`timescale 1ns/1ps
import interp_pkg::*;

module interp_pkg_tb;

  logic [7:0] p00, p10, p01, p11;
  q8_8_t fx_q, fy_q;
  logic [7:0] out;

  initial begin
    // Caso 1: fx = 0, fy = 0 => debe dar p00
    p00 = 8'd10; p10 = 8'd20;
    p01 = 8'd30; p11 = 8'd40;
    fx_q = 16'sh0000;   // 0.0
    fy_q = 16'sh0000;   // 0.0
    out  = bilinear4_u8_q8_8(p00,p10,p01,p11,fx_q,fy_q);
    $display("Caso 1: out=%0d (esperado 10)", out);

    // Caso 2: fx = 1, fy = 0 => p10
    fx_q = 16'sh0100;   // 1.0
    fy_q = 16'sh0000;   // 0.0
    out  = bilinear4_u8_q8_8(p00,p10,p01,p11,fx_q,fy_q);
    $display("Caso 2: out=%0d (esperado 20)", out);

    // Caso 3: fx = 0, fy = 1 => p01
    fx_q = 16'sh0000;   // 0.0
    fy_q = 16'sh0100;   // 1.0
    out  = bilinear4_u8_q8_8(p00,p10,p01,p11,fx_q,fy_q);
    $display("Caso 3: out=%0d (esperado 30)", out);

    // Caso 4: fx = 1, fy = 1 => p11
    fx_q = 16'sh0100;   // 1.0
    fy_q = 16'sh0100;   // 1.0
    out  = bilinear4_u8_q8_8(p00,p10,p01,p11,fx_q,fy_q);
    $display("Caso 4: out=%0d (esperado 40)", out);

    $finish;
  end

endmodule
