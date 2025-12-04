// interp_pkg.sv


package interp_pkg;

  // Número de bits fraccionarios en el punto fijo
  parameter int FRAC_BITS = 8;

  // Constante "1.0" en Q0.FRAC_BITS (por ejemplo 1.0 = 256 para FRAC_BITS = 8)
  parameter int ONE_Q = 1 << FRAC_BITS;

  // Tipos básicos
  typedef logic [7:0] u8_t;                 // píxel 8 bits
  typedef logic [15:0] q16_t;               // valor Q8.8 genérico (para coords)

  // Función de clamp a [0,255]
  function automatic u8_t clamp_u8(input integer x);
    if (x < 0)
      clamp_u8 = 8'd0;
    else if (x > 255)
      clamp_u8 = 8'd255;
    else
      clamp_u8 = u8_t'(x[7:0]);
  endfunction

endpackage
