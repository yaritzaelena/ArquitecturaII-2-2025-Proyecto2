// Proyecto2Arqui2_tb.sv
// Testbench para el top-level Proyecto2Arqui2
// - Carga una imagen real desde cameraman_512x512.hex en ram_in.
// - Configura el top en modo continuo (cmd_continue=1).
// - Selecciona modo secuencial o SIMD mediante mode_simd.
// - Genera un pulso de start.
// - Espera a que done=1.
// - Muestra algunos píxeles de la RAM de salida y vuelca toda a un .hex.
// - Imprime contadores de ciclos, lecturas y escrituras.
//
// Esto prueba en conjunto:
//   - step_controller (en modo continuo)
//   - controller_downscale (FSM SEQ/SIMD + downscaling)
//   - interp_secuencial / interp_simd4
//   - RAM de entrada/salida
//   - Señales del top (clk, rst_n, start, done, halted)

`timescale 1ns/1ps
import interp_pkg::*;

module Proyecto2Arqui2_tb;

  // Parámetros (deben coincidir con el top)
  localparam int LANES      = 4;
  localparam int FRAC       = FRAC_BITS;
  localparam int IMG_W      = 512;
  localparam int IMG_H      = 512;
  localparam int ADDR_W     = 19;

  // Factor de escala (debe coincidir con el top)
  // escala = SCALE_NUM / SCALE_DEN
  // Ejemplo: 1/2 = downscale a 0.5 (512x512 -> 256x256)
  localparam int SCALE_NUM  = 1;
  localparam int SCALE_DEN  = 2;

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

  // Instancia del DUT (top-level)
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
  // Task: inicializar RAM de entrada desde un archivo HEX
  //       (imagen real 512x512 en escala de grises)
  // --------------------------------------------------------------------------
  task automatic init_input_image_from_hex(string filename);
  begin
    $display("Cargando imagen desde %s en ram_in...", filename);
    // Acceso jerárquico a la memoria interna de la RAM de entrada
    $readmemh(filename, dut.ram_in.mem);
    $display("Imagen cargada en RAM de entrada.");
  end
  endtask

  // --------------------------------------------------------------------------
  // Task: mostrar primeros N píxeles de la RAM de salida
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
  // Task: volcar RAM de salida a archivo HEX
  // --------------------------------------------------------------------------
  task automatic dump_output_to_hex(string filename);
  begin
    $display("Volcando RAM de salida a %s ...", filename);
    $writememh(filename, dut.ram_out.mem);
    $display("Listo.");
  end
  endtask

  // --------------------------------------------------------------------------
  // Estímulo principal
  // --------------------------------------------------------------------------
  initial begin
    // Valores iniciales de control
    rst_n        = 1'b0;
    start        = 1'b0;
    cmd_step     = 1'b0;
    cmd_continue = 1'b0;
    cmd_halt     = 1'b0;

    // Selección de modo:
    //  0 -> secuencial
    //  1 -> SIMD
    mode_simd    = 1'b0;  // primero probamos el modo SECUENCIAL
    // Para probar SIMD, cambia a 1'b1 y vuelve a simular.

    // Inicializamos la RAM de entrada ANTES de soltar reset
    init_input_image_from_hex("cameraman_512x512.hex");

    // Espera unos ciclos y quita reset
    repeat (5) @(negedge clk);
    rst_n = 1'b1;
    $display("Reset desactivado en t=%0t", $time);

    // Configurar modo contínuo: cmd_continue = 1
    @(negedge clk);
    cmd_continue = 1'b1;
    cmd_halt     = 1'b0;

    // Pequeña espera y luego pulso de start
    @(negedge clk);
    $display("Enviando pulso de start en t=%0t (mode_simd = %0d)", $time, mode_simd);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;

    // Esperar a que el top termine (done=1)
    $display("Esperando done=1 ...");
    wait (done == 1'b1);
    $display("DONE se activó en t=%0t", $time);

    // Mostrar algunos píxeles de salida
    show_output_pixels(64);

    // Imprimir contadores internos del controlador
    $display("---- Performance counters (modo %0s) ----",
             mode_simd ? "SIMD" : "Secuencial");
    $display("  Ciclos       : %0d", dut.cycle_count_ctrl);
    $display("  Lecturas RAM : %0d", dut.rd_count_ctrl);
    $display("  Escrituras RAM: %0d", dut.wr_count_ctrl);

    // Volcar salida completa a archivo HEX para comparación externa
    dump_output_to_hex("top_out_image.hex");

    // Pequeña espera y fin de simulación
    #100;
    $display("======================================");
    $display("  Testbench Proyecto2Arqui2 TERMINADO");
    $display("======================================");
    $finish;
  end

endmodule



