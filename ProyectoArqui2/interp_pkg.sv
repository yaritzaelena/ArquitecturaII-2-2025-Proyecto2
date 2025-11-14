package interp_pkg;

  typedef logic signed [15:0] q8_8_t;

  function automatic q8_8_t q8_8_mul(q8_8_t a, q8_8_t b);
    logic signed [31:0] tmp;

    tmp = a * b;          // resultado en Q16.16
    tmp = tmp >>> 8;      // volver a Q8.8

    if (tmp > 16'sh7FFF)
      tmp = 16'sh7FFF;
    else if (tmp < -16'sh8000)
      tmp = -16'sh8000;

    return q8_8_t'(tmp[15:0]);
  endfunction


  // =============================
  //  Función: clamp a 0..255
  // =============================
  function automatic logic [7:0] clamp_u8(logic signed [15:0] x);
    if (x < 0)
      return 8'd0;
    else if (x > 255)
      return 8'd255;
    else
      return x[7:0]; 
  endfunction



  function automatic logic [7:0] bilinear4_u8_q8_8(
      input logic [7:0] p00, p10,
      input logic [7:0] p01, p11,
      input q8_8_t      fx_q,
      input q8_8_t      fy_q
  );
    q8_8_t one_q;
    q8_8_t wx0, wx1, wy0, wy1;
    q8_8_t top_q, bottom_q, val_q;
    logic signed [15:0] val_int;

    // 1.0 en Q8.8
    one_q = 16'sh0100;   // 0000 0001 . 0000 0000

    // Pesos en X
    wx1 = fx_q;
    wx0 = one_q - fx_q;

    // Pesos en Y
    wy1 = fy_q;
    wy0 = one_q - fy_q;

    // Interpolación en X para fila superior e inferior
    top_q    = q8_8_mul(wx0, q8_8_t'({8'b0, p00})) +
               q8_8_mul(wx1, q8_8_t'({8'b0, p10}));

    bottom_q = q8_8_mul(wx0, q8_8_t'({8'b0, p01})) +
               q8_8_mul(wx1, q8_8_t'({8'b0, p11}));

    val_q = q8_8_mul(wy0, top_q) + q8_8_mul(wy1, bottom_q);

    val_int = (val_q + 16'sh0080) >>> 8;

    return clamp_u8(val_int);
  endfunction

endpackage
