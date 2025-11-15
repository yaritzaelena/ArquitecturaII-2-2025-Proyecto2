package interp_pkg;

  // Tipo Q8.8: 8 bits enteros + 8 bits fraccionales
  typedef logic signed [15:0] q8_8_t;

  // =============================
  //  Multiplicación Q8.8 × Q8.8
  // =============================
  function automatic q8_8_t q8_8_mul (
      input q8_8_t a,
      input q8_8_t b
  );
    logic signed [31:0] tmp;
    q8_8_t r;
    begin
      // Multiplicación → resultado en Q16.16
      tmp = a * b;

      // Ajuste de escala: volver a Q8.8
      tmp = tmp >>> 8;

      // Saturación a rango válido de Q8.8
      if (tmp > 32'sh00007FFF)
        tmp = 32'sh00007FFF;
      else if (tmp < -32'sh00008000)
        tmp = -32'sh00008000;

      // Truncar a 16 bits
      r = tmp[15:0];

      // Asignar valor de retorno
      q8_8_mul = r;
    end
  endfunction

  // =============================
  //  Clamp a rango 0..255
  // =============================
  function automatic logic [7:0] clamp_u8 (
      input logic signed [15:0] x
  );
    logic [7:0] res;
    begin
      if (x < 0)
        res = 8'd0;
      else if (x > 255)
        res = 8'd255;
      else
        res = x[7:0];

      clamp_u8 = res;
    end
  endfunction

  // =============================
  //  Interpolación bilineal
  //
  //  Vecinos:
  //    p00  p10
  //    p01  p11
  //
  //  fx_q, fy_q en Q8.8 (fracción 0..1)
  // =============================
  function automatic logic [7:0] bilinear4_u8_q8_8 (
      input logic [7:0] p00, p10,
      input logic [7:0] p01, p11,
      input q8_8_t      fx_q,
      input q8_8_t      fy_q
  );
    // locales
    q8_8_t one_q;
    q8_8_t wx0, wx1, wy0, wy1;
    q8_8_t p00_q, p10_q, p01_q, p11_q;
    q8_8_t top_q, bottom_q, val_q;
    logic signed [15:0] val_int;
    logic [7:0] res;
    begin
      // 1.0 en Q8.8
      one_q = 16'sh0100;

      // Pesos en X
      wx1 = fx_q;
      wx0 = one_q - fx_q;

      // Pesos en Y
      wy1 = fy_q;
      wy0 = one_q - fy_q;

      // Convertir píxeles 0..255 a Q8.8 (x256)
      p00_q = q8_8_t'({p00, 8'b0});  // p00 << 8
      p10_q = q8_8_t'({p10, 8'b0});  // p10 << 8
      p01_q = q8_8_t'({p01, 8'b0});  // p01 << 8
      p11_q = q8_8_t'({p11, 8'b0});  // p11 << 8

      // Interpolación horizontal
      top_q    = q8_8_mul(wx0, p00_q) +
                 q8_8_mul(wx1, p10_q);

      bottom_q = q8_8_mul(wx0, p01_q) +
                 q8_8_mul(wx1, p11_q);

      // Interpolación vertical
      val_q = q8_8_mul(wy0, top_q) + q8_8_mul(wy1, bottom_q);

      // Redondeo: sumar 0.5 (128 en Q8.8) antes de truncar
      val_int = (val_q + 16'sh0080) >>> 8;

      // Clamp final a 0..255
      res = clamp_u8(val_int);

      // Valor de retorno
      bilinear4_u8_q8_8 = res;
    end
  endfunction

endpackage
