`timescale 1ns/1ps
import interp_pkg::*;

module Proyecto2Arqui2_tb;

  // Parámetros (deben coincidir con el top)
  localparam int LANES      = 4;
  localparam int FRAC       = FRAC_BITS;
  localparam int IMG_W      = 512;
  localparam int IMG_H      = 512;
  localparam int ADDR_W     = 19;

  // Escala global (mismo valor para SEQ y SIMD4)
  localparam int SCALE_NUM  = 3;
  localparam int SCALE_DEN  = 4;  // 0.5

  // Señales hacia el top
  logic clk;
  logic rst_n;
  logic start;
  logic cmd_step;
  logic cmd_continue;
  logic cmd_halt;
  logic done;
  logic halted;
  logic mode_simd;  // 0 = secuencial, 1 = SIMD

  // DUT
  Proyecto2Arqui2 #(
    .LANES     (LANES),
    .FRAC      (FRAC),
    .IMG_W     (IMG_W),
    .IMG_H     (IMG_H),
    .ADDR_W    (ADDR_W),
    .SCALE_NUM (SCALE_NUM),
    .SCALE_DEN (SCALE_DEN)
  ) dut (
    .clk         (clk),
    .rst_n       (rst_n),
    .start       (start),
    .cmd_step    (cmd_step),
    .cmd_continue(cmd_continue),
    .cmd_halt    (cmd_halt),
    .mode_simd   (mode_simd),
    .done        (done),
    .halted      (halted)
  );

  // --------------------------------------------------------------------------
  // Reloj
  // --------------------------------------------------------------------------
  initial clk = 1'b0;
  always #5 clk = ~clk;   // 100 MHz

  // --------------------------------------------------------------------------
  // Task: inicializar RAM de entrada desde HEX
  // --------------------------------------------------------------------------
  task automatic init_input_image_from_hex(string filename);
  begin
    $display("Cargando imagen desde %s en ram_in...", filename);
    $readmemh(filename, dut.ram_in.mem);
    $display("Imagen cargada en RAM de entrada.");
  end
  endtask

  // --------------------------------------------------------------------------
  // Task: volcar RAM de salida a HEX
  // --------------------------------------------------------------------------
  task automatic dump_output_to_hex(string filename);
  begin
    $display("Volcando RAM de salida a %s ...", filename);
    $writememh(filename, dut.ram_out.mem);
    $display("Listo.");
  end
  endtask

  // --------------------------------------------------------------------------
  // Task: mostrar primeros N píxeles de salida (solo debug)
  // --------------------------------------------------------------------------
  task automatic show_output_pixels(int N);
    integer i;
  begin
    $display("===== RAM OUTPUT (primeros %0d valores) =====", N);
    for (i = 0; i < N; i++) begin
      $display("out[%0d] = %0d", i, dut.ram_out.mem[i]);
    end
  end
  endtask

  // --------------------------------------------------------------------------
  // Estímulo principal: primero SEQ, luego SIMD
  // --------------------------------------------------------------------------
  initial begin
    // Valores iniciales
    rst_n        = 1'b0;
    start        = 1'b0;
    cmd_step     = 1'b0;
    cmd_continue = 1'b0;
    cmd_halt     = 1'b0;
    mode_simd    = 1'b0;   // empezamos en SECUENCIAL

    // ======================================================
    // 1) MODO SECUENCIAL
    // ======================================================
    init_input_image_from_hex("cameraman_512x512.hex");

    repeat (5) @(negedge clk);
    rst_n = 1'b1;
    $display("Reset desactivado (SEQ) t=%0t", $time);

    @(negedge clk);
    cmd_continue = 1'b1;
    cmd_halt     = 1'b0;

    @(negedge clk);
    $display("Enviando start (SEQ) t=%0t", $time);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;

    $display("Esperando done (SEQ)...");
    wait (done == 1'b1);
    $display("DONE SEQ en t=%0t", $time);

    show_output_pixels(32);
    dump_output_to_hex("top_out_seq.hex");

    // ======================================================
    // 2) MODO SIMD4
    // ======================================================
    $display("\n======================================");
    $display("  CAMBIANDO A MODO SIMD4");
    $display("======================================");

    // Reset "limpio"
    @(negedge clk);
    rst_n        = 1'b0;
    cmd_continue = 1'b0;
    start        = 1'b0;
    @(negedge clk);
    rst_n        = 1'b1;

    // Recargamos imagen de entrada (por claridad)
    init_input_image_from_hex("cameraman_512x512.hex");

    @(negedge clk);
    mode_simd    = 1'b1;   // ahora SIMD
    cmd_continue = 1'b1;
    cmd_halt     = 1'b0;

    @(negedge clk);
    $display("Enviando start (SIMD) t=%0t", $time);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;

    $display("Esperando done (SIMD)...");
    wait (done == 1'b1);
    $display("DONE SIMD en t=%0t", $time);

    show_output_pixels(32);
    dump_output_to_hex("top_out_simd.hex");

    // Fin
    #100;
    $display("======================================");
    $display("  Testbench Proyecto2Arqui2 TERMINADO");
    $display("======================================");
    $finish;
  end

endmodule

