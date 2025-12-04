// interp_secuencial_tb.sv
// Testbench dirigido para validar interp_secuencial.sv
// Asume FRAC_BITS = 8 (Q0.8). Si cambias FRAC_BITS, los valores
// esperados deben recalcularse.

`timescale 1ns/1ps
import interp_pkg::*;   // Debe definir FRAC_BITS, u8_t, clamp_u8, etc.

module interp_secuencial_tb;

  localparam int FRAC = FRAC_BITS;

  // Señales DUT
  logic        clk;
  logic        rst_n;

  logic        valid_in;
  u8_t         p00, p10, p01, p11;
  logic [FRAC-1:0] fx, fy;

  logic        valid_out;
  u8_t         pixel_out;

  // --------------------------------------------------------------------------
  // Instancia del DUT
  // --------------------------------------------------------------------------
  interp_secuencial #(
    .FRAC(FRAC)
  ) dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .valid_in  (valid_in),
    .p00       (p00),
    .p10       (p10),
    .p01       (p01),
    .p11       (p11),
    .fx        (fx),
    .fy        (fy),
    .valid_out (valid_out),
    .pixel_out (pixel_out)
  );

  // --------------------------------------------------------------------------
  // Reloj
  // --------------------------------------------------------------------------
  initial clk = 1'b0;
  always #5 clk = ~clk;  // 100 MHz

  // --------------------------------------------------------------------------
  // Task: aplica un caso y comprueba contra valor esperado
  // --------------------------------------------------------------------------
  task automatic apply_case(
    input u8_t              p00_i,
    input u8_t              p10_i,
    input u8_t              p01_i,
    input u8_t              p11_i,
    input logic [FRAC-1:0]  fx_i,
    input logic [FRAC-1:0]  fy_i,
    input u8_t              expected,
    input string            name
  );
  begin
    // Aplicar estímulos en flanco negativo
    @(negedge clk);
    p00      <= p00_i;
    p10      <= p10_i;
    p01      <= p01_i;
    p11      <= p11_i;
    fx       <= fx_i;
    fy       <= fy_i;
    valid_in <= 1'b1;

    // Un ciclo con valid_in = 1
    @(negedge clk);
    valid_in <= 1'b0;

    // Esperar un ciclo (latencia de 1) y revisar salida
    @(posedge clk);

    if (valid_out !== 1'b1) begin
      $display("[ERROR] %-25s: valid_out no se activó. time=%0t",
               name, $time);
    end
    else if (pixel_out !== expected) begin
      $display("[ERROR] %-25s: pixel_out=%0d, esperado=%0d (fx=%0d, fy=%0d) time=%0t",
               name, pixel_out, expected, fx_i, fy_i, $time);
    end
    else begin
      $display("[OK]    %-25s: pixel_out=%0d, esperado=%0d (fx=%0d, fy=%0d) time=%0t",
               name, pixel_out, expected, fx_i, fy_i, $time);
    end
  end
  endtask

  // --------------------------------------------------------------------------
  // Estímulo principal
  // --------------------------------------------------------------------------
  initial begin
    // Inicialización
    rst_n    = 1'b0;
    valid_in = 1'b0;
    p00 = '0; p10 = '0; p01 = '0; p11 = '0;
    fx  = '0; fy  = '0;

    // Reset
    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    // ============================================================
    // Casos dirigidos con respuesta conocida (FRAC_BITS = 8)
    // Todos estos valores de salida se calcularon EXACTO con la
    // misma aritmética que usa el módulo (Q0.8, restas, shifts, etc.)
    // ============================================================

    // 1) Todos iguales, fx=0, fy=0 -> debe dar p00
    //    p00 = p10 = p01 = p11 = 50
    //    esperado = 50
    apply_case(8'd50, 8'd50, 8'd50, 8'd50,
               8'd0, 8'd0,
               8'd50,
               "all50_fx0_fy0");

    // 2) Todos iguales, fx=255, fy=255
    //    por truncamientos, el resultado es 99 (no 100)
    apply_case(8'd100, 8'd100, 8'd100, 8'd100,
               8'd255, 8'd255,
               8'd99,
               "all100_fxmax_fymax");

    // 3) Interpolación horizontal simple entre 0 y 255, fy=0
    //    p00=0, p10=255, p01=0, p11=255
    //    fx=0   -> 0
    apply_case(8'd0, 8'd255, 8'd0, 8'd255,
               8'd0, 8'd0,
               8'd0,
               "horiz_0_255_fx0");

    //    fx=128 (~0.5) -> 127
    apply_case(8'd0, 8'd255, 8'd0, 8'd255,
               8'd128, 8'd0,
               8'd127,
               "horiz_0_255_fxhalf");

    //    fx=255 (~1.0) -> 254
    apply_case(8'd0, 8'd255, 8'd0, 8'd255,
               8'd255, 8'd0,
               8'd254,
               "horiz_0_255_fxmax");

    // 4) Interpolación vertical simple entre 0 y 255, fx=0
    //    p00=0, p10=0, p01=255, p11=255
    //    fy=0   -> 0
    apply_case(8'd0, 8'd0, 8'd255, 8'd255,
               8'd0, 8'd0,
               8'd0,
               "vert_0_255_fy0");

    //    fy=128 (~0.5) -> 127
    apply_case(8'd0, 8'd0, 8'd255, 8'd255,
               8'd0, 8'd128,
               8'd127,
               "vert_0_255_fyhalf");

    //    fy=255 (~1.0) -> 254
    apply_case(8'd0, 8'd0, 8'd255, 8'd255,
               8'd0, 8'd255,
               8'd254,
               "vert_0_255_fymax");

    // 5) Caso diagonal:
    //    p00=0, p10=255, p01=255, p11=0
    //    fx=fy=128 (~0.5, 0.5) -> 127
    apply_case(8'd0, 8'd255, 8'd255, 8'd0,
               8'd128, 8'd128,
               8'd127,
               "diag_case");

    // Fin de pruebas
    $display("======================================");
    $display("  Testbench interp_secuencial TERMINADO");
    $display("======================================");
    #50;
    $finish;
  end

endmodule
