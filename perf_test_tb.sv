// perf_test_tb.sv
// Testbench para medir rendimiento (ciclos, ciclos/pixel, speedup)
// entre el modo Secuencial y el modo SIMD-4

`timescale 1ns/1ps
import interp_pkg::*;

module perf_test_tb;

  // -------------------------------
  // Parámetros de la prueba
  // -------------------------------
  localparam int W_IN  = 8;
  localparam int H_IN  = 4;
  localparam real SCALE_REAL = 0.5;
  localparam int  SCALE_Q    = int'(SCALE_REAL * (1 << FRAC_BITS));

  localparam int W_OUT = (W_IN * SCALE_Q) >>> FRAC_BITS;  // =4
  localparam int H_OUT = (H_IN * SCALE_Q) >>> FRAC_BITS;  // =2

  localparam int LANES = 4;

  // -------------------------------
  // Señales generales
  // -------------------------------
  logic clk;
  logic rst_n;

  // -------------------------------------------------------------------
  // Núcleo Secuencial
  // -------------------------------------------------------------------
  logic        valid_in_seq;
  u8_t         p00_s, p10_s, p01_s, p11_s;
  logic [7:0]  fx_s, fy_s;
  logic        valid_out_seq;
  u8_t         pixel_out_seq;

  // -------------------------------------------------------------------
  // Núcleo SIMD-4
  // -------------------------------------------------------------------
  logic             valid_in_simd;
  u8_t              p00_vec[LANES];
  u8_t              p10_vec[LANES];
  u8_t              p01_vec[LANES];
  u8_t              p11_vec[LANES];
  logic [7:0]       fx_vec [LANES];
  logic [7:0]       fy_vec [LANES];

  logic             valid_out_simd;
  u8_t              pixel_out_vec[LANES];

  // -------------------------------------------------------------------
  // Instancias
  // -------------------------------------------------------------------
  interp_secuencial dut_seq (
    .clk        (clk),
    .rst_n      (rst_n),
    .valid_in   (valid_in_seq),
    .p00        (p00_s),
    .p10        (p10_s),
    .p01        (p01_s),
    .p11        (p11_s),
    .fx         (fx_s),
    .fy         (fy_s),
    .valid_out  (valid_out_seq),
    .pixel_out  (pixel_out_seq)
  );

  interp_simd4 #(
    .LANES (LANES),
    .FRAC  (FRAC_BITS)
  ) dut_simd (
    .clk           (clk),
    .rst_n         (rst_n),
    .valid_in      (valid_in_simd),
    .p00_vec       (p00_vec),
    .p10_vec       (p10_vec),
    .p01_vec       (p01_vec),
    .p11_vec       (p11_vec),
    .fx_vec        (fx_vec),
    .fy_vec        (fy_vec),
    .valid_out     (valid_out_simd),
    .pixel_out_vec (pixel_out_vec)
  );

  // -------------------------------
  // Clock
  // -------------------------------
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end


  // ==========================================================
  // Tareas: Simulación SECUENCIAL y SIMD-4
  // ==========================================================

  integer cycle_count_seq;
  integer cycle_count_simd;
  integer y_out, x_out, lane;

  task run_sequential;
    begin
      cycle_count_seq = 0;

      $display("\n=== MIDIENTO MODO SECUENCIAL ===");

      // Recorremos cada píxel individualmente
      for (y_out = 0; y_out < H_OUT; y_out++) begin
        for (x_out = 0; x_out < W_OUT; x_out++) begin

          // Señales dummy
          p00_s = 8'h10;
          p10_s = 8'h20;
          p01_s = 8'h30;
          p11_s = 8'h40;
          fx_s  = 8'h80;
          fy_s  = 8'h40;

          @(posedge clk);
          valid_in_seq <= 1'b1;

          @(posedge clk);
          valid_in_seq <= 1'b0;

          // Esperar salida
          @(posedge clk);
          if (!valid_out_seq)
            $display("Warning: secuencial sin valid_out donde se esperaba");
          
          cycle_count_seq += 1;
        end
      end

      $display("Ciclos totales (Secuencial) = %0d", cycle_count_seq);
    end
  endtask


  task run_simd4;
    begin
      cycle_count_simd = 0;

      $display("\n=== MIDIENTO MODO SIMD-4 ===");

      // Como W_OUT=4, solo 1 bloque por fila
      for (y_out = 0; y_out < H_OUT; y_out++) begin

        // Preparar datos dummy
        for (lane = 0; lane < LANES; lane++) begin
          p00_vec[lane] = 8'h10 + lane;
          p10_vec[lane] = 8'h20 + lane;
          p01_vec[lane] = 8'h30 + lane;
          p11_vec[lane] = 8'h40 + lane;
          fx_vec[lane]  = 8'h80;
          fy_vec[lane]  = 8'h40;
        end

        @(posedge clk);
        valid_in_simd <= 1'b1;

        @(posedge clk);
        valid_in_simd <= 1'b0;

        @(posedge clk);
        if (!valid_out_simd)
          $display("Warning: SIMD sin valid_out donde se esperaba");

        cycle_count_simd += 1;
      end

      $display("Ciclos totales (SIMD-4) = %0d", cycle_count_simd);
    end
  endtask


  // ===================================================
  // Control principal + Estadísticas de rendimiento
  // ===================================================

  integer pix_total;
  real cp_seq, cp_simd;
  real speedup;

  initial begin
    rst_n = 0;
    valid_in_seq  = 0;
    valid_in_simd = 0;

    repeat (5) @(posedge clk);
    rst_n = 1;

    @(posedge clk);

    // ---- medir SECUENCIAL ----
    run_sequential();

    // ---- medir SIMD ----
    run_simd4();

    // ---- cálculos ----
    pix_total = W_OUT * H_OUT;

    cp_seq  = cycle_count_seq  * 1.0 / pix_total;
    cp_simd = cycle_count_simd * 1.0 / pix_total;

    speedup = cp_seq / cp_simd;

    // ---- imprimir resumen ----
    $display("\n----------------------------------");
    $display("Píxeles totales = %0d", pix_total);
    $display("----------------------------------");

    $display("\n[SECUENCIAL]");
    $display(" Ciclos totales  = %0d", cycle_count_seq);
    $display(" Ciclos/píxel    = %0.3f", cp_seq);

    $display("\n[SIMD-4]");
    $display(" Ciclos totales  = %0d", cycle_count_simd);
    $display(" Ciclos/píxel    = %0.3f", cp_simd);

    $display("\n===================================");
    $display(" SPEEDUP = %0.3f X", speedup);
    $display("===================================\n");

    $display("Prueba de rendimiento completada.\n");
    $stop;
  end

endmodule
