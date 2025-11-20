`timescale 1ns/1ps

import interp_pkg::*;

module interp_secuencial_tb;

  // ==========================
  // Parámetros de la prueba
  // ==========================

  localparam int W_IN  = 4;
  localparam int H_IN  = 4;

  // Escala 0.5 -> imagen 2x2
  localparam real SCALE_REAL = 0.5;
  localparam int  W_OUT = 2;
  localparam int  H_OUT = 2;

  // Factor de escala en Q8.8 (0.5 * 256 = 128)
  localparam int SCALE_Q = int'(SCALE_REAL * (1 << FRAC_BITS));

  // RAM para la imagen de entrada (4x4 = 16 píxeles => 4 bits de addr)
  localparam int ADDR_WIDTH = 4;

  // ==========================
  // Señales
  // ==========================

  logic clk;
  logic rst_n;

  // Núcleo bajo prueba
  logic        valid_in;
  u8_t         p00, p10, p01, p11;
  logic [7:0]  fx, fy;
  logic        valid_out;
  u8_t         pixel_out;

  // RAM de imagen de entrada
  logic                    we_in;
  logic [ADDR_WIDTH-1:0]   addr_in;
  logic [7:0]              wdata_in;
  logic [7:0]              rdata_in;

  // Imagenes
  u8_t img_in    [0:H_IN-1][0:W_IN-1];
  u8_t img_out_hw[0:H_OUT-1][0:W_OUT-1];
  u8_t img_out_sw[0:H_OUT-1][0:W_OUT-1];

  // Vecinos locales (declarados a nivel de módulo, NO dentro del for)
  u8_t p00_loc, p10_loc, p01_loc, p11_loc;

  // ==========================
  // Instancias
  // ==========================

  ram_img #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (8)
  ) ram_in (
    .clk   (clk),
    .we    (we_in),
    .addr  (addr_in),
    .wdata (wdata_in),
    .rdata (rdata_in)
  );

  interp_secuencial dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .valid_in   (valid_in),
    .p00        (p00),
    .p10        (p10),
    .p01        (p01),
    .p11        (p11),
    .fx         (fx),
    .fy         (fy),
    .valid_out  (valid_out),
    .pixel_out  (pixel_out)
  );

  // ==========================
  // Clock
  // ==========================

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // ==========================
  // Modelo de referencia
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
      for (y = 0; y < H_IN; y++) begin
        for (x = 0; x < W_IN; x++) begin
          img_in[y][x] = u8_t'(y*W_IN*16 + x*16);
        end
      end
    end
  endtask

  task automatic load_image_to_ram;
    int idx, x, y;
    begin
      we_in = 1'b1;
      idx   = 0;
      for (y = 0; y < H_IN; y++) begin
        for (x = 0; x < W_IN; x++) begin
          @(posedge clk);
          addr_in  = idx[ADDR_WIDTH-1:0];
          wdata_in = img_in[y][x];
          idx++;
        end
      end
      @(posedge clk);
      we_in = 1'b0;
    end
  endtask

  // === task en vez de function con @(posedge)
  task automatic read_pixel_from_ram(
    input int x,
    input int y,
    output u8_t pix
  );
    int addr_lin;
    begin
      addr_lin = y*W_IN + x;
      addr_in  = addr_lin[ADDR_WIDTH-1:0];
      @(posedge clk);
      pix = rdata_in;
    end
  endtask

  // ==========================
  // Estímulos principales
  // ==========================

  int x_out, y_out;
  int x_q, y_q;
  int x0, x1, y0, y1;
  int fx_q, fy_q;
  int W_out_calc, H_out_calc;

  initial begin
    rst_n    = 1'b0;
    valid_in = 1'b0;
    we_in    = 1'b0;
    addr_in  = '0;
    wdata_in = '0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;

    init_input_image();
    load_image_to_ram();

    W_out_calc = (W_IN * SCALE_Q) >>> FRAC_BITS;
    H_out_calc = (H_IN * SCALE_Q) >>> FRAC_BITS;

    $display("W_OUT esperado = %0d (const = %0d)", W_out_calc, W_OUT);
    $display("H_OUT esperado = %0d (const = %0d)", H_out_calc, H_OUT);

    // Recorremos todos los píxeles de salida
    for (y_out = 0; y_out < H_OUT; y_out++) begin
      for (x_out = 0; x_out < W_OUT; x_out++) begin

        x_q = (x_out << FRAC_BITS) * (1 << FRAC_BITS) / SCALE_Q;
        y_q = (y_out << FRAC_BITS) * (1 << FRAC_BITS) / SCALE_Q;

        x0   = x_q >>> FRAC_BITS;
        y0   = y_q >>> FRAC_BITS;
        fx_q = x_q & ((1 << FRAC_BITS) - 1);
        fy_q = y_q & ((1 << FRAC_BITS) - 1);

        if (x0 < 0)       x0 = 0;
        if (x0 >= W_IN-1) x0 = W_IN-2;
        if (y0 < 0)       y0 = 0;
        if (y0 >= H_IN-1) y0 = H_IN-2;

        x1 = x0 + 1;
        y1 = y0 + 1;

        // Leemos vecinos con el task
        read_pixel_from_ram(x0, y0, p00_loc);
        read_pixel_from_ram(x1, y0, p10_loc);
        read_pixel_from_ram(x0, y1, p01_loc);
        read_pixel_from_ram(x1, y1, p11_loc);

        img_out_sw[y_out][x_out] = bilinear_ref(
          p00_loc, p10_loc, p01_loc, p11_loc,
          logic'(fx_q[7:0]), logic'(fy_q[7:0])
        );

        @(posedge clk);
        valid_in <= 1'b1;
        p00      <= p00_loc;
        p10      <= p10_loc;
        p01      <= p01_loc;
        p11      <= p11_loc;
        fx       <= fx_q[7:0];
        fy       <= fy_q[7:0];

        @(posedge clk);
        valid_in <= 1'b0;

        @(posedge clk);
        if (valid_out) begin
          img_out_hw[y_out][x_out] = pixel_out;
          if (pixel_out !== img_out_sw[y_out][x_out]) begin
            $display("MISMATCH (%0d,%0d): HW=%0d SW=%0d",
                     x_out, y_out, pixel_out, img_out_sw[y_out][x_out]);
          end else begin
            $display("OK (%0d,%0d): valor=%0d",
                     x_out, y_out, pixel_out);
          end
        end else begin
          $display("ERROR: valid_out no activo cuando se esperaba");
        end
      end
    end

    $display("Prueba completada.");
    $stop;
  end

endmodule
