// interp_simd4_tb.sv
// Testbench para núcleo SIMD-4: procesa 4 píxeles por ciclo

`timescale 1ns/1ps
import interp_pkg::*;

module interp_simd4_tb;

  // ==========================
  // Parámetros de la prueba
  // ==========================

  localparam int LANES   = 4;
  localparam int W_IN    = 8;
  localparam int H_IN    = 4;

  localparam real SCALE_REAL = 0.5;
  localparam int  SCALE_Q    = int'(SCALE_REAL * (1 << FRAC_BITS));

  localparam int W_OUT  = (W_IN * SCALE_Q) >>> FRAC_BITS; // 4
  localparam int H_OUT  = (H_IN * SCALE_Q) >>> FRAC_BITS; // 2

  // ==========================
  // Señales
  // ==========================

  logic clk;
  logic rst_n;

  logic             valid_in;
  u8_t              p00_vec   [LANES];
  u8_t              p10_vec   [LANES];
  u8_t              p01_vec   [LANES];
  u8_t              p11_vec   [LANES];
  logic [7:0]       fx_vec    [LANES];
  logic [7:0]       fy_vec    [LANES];

  logic             valid_out;
  u8_t              pixel_out_vec [LANES];

  // Imagen de entrada y salidas de referencia/HW
  u8_t img_in    [0:H_IN-1][0:W_IN-1];
  u8_t img_out_sw[0:H_OUT-1][0:W_OUT-1];
  u8_t img_out_hw[0:H_OUT-1][0:W_OUT-1];

  // ==========================
  // Instancia del DUT
  // ==========================

  interp_simd4 #(
    .LANES (LANES),
    .FRAC  (FRAC_BITS)
  ) dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .valid_in       (valid_in),
    .p00_vec        (p00_vec),
    .p10_vec        (p10_vec),
    .p01_vec        (p01_vec),
    .p11_vec        (p11_vec),
    .fx_vec         (fx_vec),
    .fy_vec         (fy_vec),
    .valid_out      (valid_out),
    .pixel_out_vec  (pixel_out_vec)
  );

  // ==========================
  // Clock
  // ==========================

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  // ==========================
  // Modelo de referencia (igual al secuencial)
  // ==========================

  function automatic u8_t bilinear_ref(
    input u8_t p00_i, input u8_t p10_i,
    input u8_t p01_i, input u8_t p11_i,
    input logic [7:0] fx_i, input logic [7:0] fy_i
  );
    logic [8:0] fx_ext, fy_ext;
    logic [8:0] wx0, wx1, wy0, wy1;
    logic [17:0] mult00, mult10, mult01, mult11;
    logic [8:0]  w00, w10, w01, w11;
    logic [31:0] term00, term10, term01, term11;
    logic [31:0] sum_q;
    integer      sum_int;

    fx_ext = {1'b0, fx_i};
    fy_ext = {1'b0, fy_i};

    wx1 = fx_ext;
    wy1 = fy_ext;
    wx0 = ONE_Q - fx_ext;
    wy0 = ONE_Q - fy_ext;

    mult00 = wx0 * wy0;
    mult10 = wx1 * wy0;
    mult01 = wx0 * wy1;
    mult11 = wx1 * wy1;

    w00 = mult00 >> FRAC_BITS;
    w10 = mult10 >> FRAC_BITS;
    w01 = mult01 >> FRAC_BITS;
    w11 = mult11 >> FRAC_BITS;

    term00 = p00_i * w00;
    term10 = p10_i * w10;
    term01 = p01_i * w01;
    term11 = p11_i * w11;

    sum_q   = term00 + term10 + term01 + term11;
    sum_int = sum_q >>> FRAC_BITS;

    return clamp_u8(sum_int);
  endfunction

  // ==========================
  // Inicializar imagen
  // ==========================

  task automatic init_input_image;
    int x, y;
    begin
      // Gradiente simple para distinguir píxeles
      for (y = 0; y < H_IN; y++) begin
        for (x = 0; x < W_IN; x++) begin
          img_in[y][x] = u8_t'(y*W_IN*8 + x*8);
        end
      end
    end
  endtask

  // ==========================
  // Estímulos principales
  // ==========================

  int y_out;
  int x_out_base;
  int lane;
  int x_out_lane;
  int x_q, y_q;
  int x0, x1, y0, y1;
  int fx_q, fy_q;

  initial begin
    rst_n    = 1'b0;
    valid_in = 1'b0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;

    init_input_image();

    $display("W_OUT = %0d, H_OUT = %0d", W_OUT, H_OUT);
    if (W_OUT != 4 || H_OUT != 2) begin
      $display("WARNING: dimensiones de salida esperadas 4x2 para esta prueba");
    end

    // Recorremos la imagen de salida en bloques de 4 píxeles (SIMD-4)
    for (y_out = 0; y_out < H_OUT; y_out++) begin
      // Como W_OUT = 4, solo un bloque: x_out_base = 0
      for (x_out_base = 0; x_out_base < W_OUT; x_out_base += LANES) begin

        // Preparamos datos para cada lane
        for (lane = 0; lane < LANES; lane++) begin
          x_out_lane = x_out_base + lane;

          // Por seguridad, aunque aquí W_OUT = 4
          if (x_out_lane >= W_OUT) begin
            // Lane inactivo (no debería ocurrir en esta prueba)
            p00_vec[lane] = '0;
            p10_vec[lane] = '0;
            p01_vec[lane] = '0;
            p11_vec[lane] = '0;
            fx_vec[lane]  = '0;
            fy_vec[lane]  = '0;
          end else begin
            // Coordenadas fuente en Q8.8
            x_q = (x_out_lane << FRAC_BITS) * (1 << FRAC_BITS) / SCALE_Q;
            y_q = (y_out       << FRAC_BITS) * (1 << FRAC_BITS) / SCALE_Q;

            x0   = x_q >>> FRAC_BITS;
            y0   = y_q >>> FRAC_BITS;
            fx_q = x_q & ((1 << FRAC_BITS) - 1);
            fy_q = y_q & ((1 << FRAC_BITS) - 1);

            if (x0 < 0)        x0 = 0;
            if (x0 >= W_IN-1)  x0 = W_IN-2;
            if (y0 < 0)        y0 = 0;
            if (y0 >= H_IN-1)  y0 = H_IN-2;

            x1 = x0 + 1;
            y1 = y0 + 1;

            // Vecinos desde img_in (no usamos RAM aquí)
            p00_vec[lane] = img_in[y0][x0];
            p10_vec[lane] = img_in[y0][x1];
            p01_vec[lane] = img_in[y1][x0];
            p11_vec[lane] = img_in[y1][x1];

            fx_vec[lane]  = logic'(fx_q[7:0]);
            fy_vec[lane]  = logic'(fy_q[7:0]);

            // Guardar referencia SW
            img_out_sw[y_out][x_out_lane] = bilinear_ref(
              p00_vec[lane], p10_vec[lane],
              p01_vec[lane], p11_vec[lane],
              fx_vec[lane],  fy_vec[lane]
            );
          end
        end

        // Enviar vector de 4 píxeles al DUT
        @(posedge clk);
        valid_in <= 1'b1;

        @(posedge clk);
        valid_in <= 1'b0;

        // Esperar salida
        @(posedge clk);
        if (valid_out) begin
          for (lane = 0; lane < LANES; lane++) begin
            x_out_lane = x_out_base + lane;
            if (x_out_lane < W_OUT) begin
              img_out_hw[y_out][x_out_lane] = pixel_out_vec[lane];

              if (pixel_out_vec[lane] !== img_out_sw[y_out][x_out_lane]) begin
                $display("MISMATCH lane%0d (x=%0d,y=%0d): HW=%0d SW=%0d",
                         lane, x_out_lane, y_out,
                         pixel_out_vec[lane],
                         img_out_sw[y_out][x_out_lane]);
              end else begin
                $display("OK lane%0d (x=%0d,y=%0d): %0d",
                         lane, x_out_lane, y_out,
                         pixel_out_vec[lane]);
              end
            end
          end
        end else begin
          $display("ERROR: valid_out no activo en ciclo esperado");
        end

      end
    end

    $display("Prueba SIMD-4 completada.");
    $stop;
  end

endmodule
