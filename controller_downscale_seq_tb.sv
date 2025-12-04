`timescale 1ns/1ps
import interp_pkg::*;

module controller_downscale_seq_tb;

  // Parámetros (coinciden con tu diseño)
  localparam int FRAC   = FRAC_BITS;
  localparam int IMG_W  = 512;
  localparam int IMG_H  = 512;
  localparam int ADDR_W = 19;

  // Señales
  logic clk;
  logic rst_n;
  logic allow_tick;
  logic start;
  logic done;

  logic [1:0] scale_mode; // 00:1.0, 01:0.75, 10:0.5

  // RAM entrada
  logic              in_we;
  logic [ADDR_W-1:0] in_addr;
  logic [7:0]        in_wdata;
  logic [7:0]        in_rdata;

  // RAM salida
  logic              out_we;
  logic [ADDR_W-1:0] out_addr;
  logic [7:0]        out_wdata;
  logic [7:0]        out_rdata;

  // contadores
  logic [31:0] cycle_count;
  logic [31:0] rd_count;
  logic [31:0] wr_count;

  // ----------------------------------------------------------------
  // Instancias de RAM (igual que en el top)
  // ----------------------------------------------------------------
  ram_img #(
    .ADDR_WIDTH(ADDR_W),
    .DATA_WIDTH(8)
  ) ram_in (
    .clk   (clk),
    .we    (in_we),
    .addr  (in_addr),
    .wdata (in_wdata),
    .rdata (in_rdata)
  );

  ram_img #(
    .ADDR_WIDTH(ADDR_W),
    .DATA_WIDTH(8)
  ) ram_out (
    .clk   (clk),
    .we    (out_we),
    .addr  (out_addr),
    .wdata (out_wdata),
    .rdata (out_rdata)
  );

  // ----------------------------------------------------------------
  // DUT: solo el controlador secuencial
  // ----------------------------------------------------------------
  controller_downscale_seq #(
    .FRAC   (FRAC),
    .IMG_W  (IMG_W),
    .IMG_H  (IMG_H),
    .ADDR_W (ADDR_W)
  ) dut (
    .clk        (clk),
    .rst_n      (rst_n),

    .allow_tick (allow_tick),
    .start      (start),
    .done       (done),

    .scale_mode (scale_mode),

    .in_we      (in_we),
    .in_addr    (in_addr),
    .in_wdata   (in_wdata),
    .in_rdata   (in_rdata),

    .out_we     (out_we),
    .out_addr   (out_addr),
    .out_wdata  (out_wdata),

    .cycle_count(cycle_count),
    .rd_count   (rd_count),
    .wr_count   (wr_count)
  );

  // ----------------------------------------------------------------
  // Reloj
  // ----------------------------------------------------------------
  initial clk = 1'b0;
  always #5 clk = ~clk; // 100 MHz

  // ----------------------------------------------------------------
  // Task: cargar imagen de entrada
  // ----------------------------------------------------------------
  task automatic init_input_image_from_hex(string filename);
  begin
    $display("Cargando imagen desde %s en ram_in...", filename);
    $readmemh(filename, ram_in.mem);
    $display("Imagen cargada en RAM de entrada.");
  end
  endtask

  // ----------------------------------------------------------------
  // Task: volcar salida a HEX
  // ----------------------------------------------------------------
  task automatic dump_output_to_hex(string filename);
  begin
    $display("Volcando RAM de salida a %s ...", filename);
    $writememh(filename, ram_out.mem);
    $display("Listo.");
  end
  endtask

  // ----------------------------------------------------------------
  // Estímulo: probamos 3 escalas seguidas
  // ----------------------------------------------------------------
  initial begin
    // Init
    rst_n      = 1'b0;
    start      = 1'b0;
    allow_tick = 1'b1;  // sin stepping, correr libre

    // Carga imagen 512x512
    init_input_image_from_hex("cameraman_512x512.hex");

    // Reset
    repeat (5) @(negedge clk);
    rst_n = 1'b1;
    $display("Reset desactivado en t=%0t", $time);

    //-----------------------------------------------------------------
    // 1) Escala 0.5
    //-----------------------------------------------------------------
    scale_mode = 2'b10;  // 0.5
    $display("===== Probando escala 0.5 =====");

    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;

    wait (done);
    $display("DONE 0.5 en t=%0t", $time);
    $display("Ciclos: %0d  Lecturas: %0d  Escrituras: %0d",
             cycle_count, rd_count, wr_count);
    dump_output_to_hex("out_scale05.hex");

    //-----------------------------------------------------------------
    // 2) Escala 0.75
    //-----------------------------------------------------------------
    // Limpiar done/start y contadores (reset suave)
    @(negedge clk);
    rst_n      = 1'b0;
    @(negedge clk);
    rst_n      = 1'b1;
    start      = 1'b0;

    scale_mode = 2'b01;  // 0.75
    $display("===== Probando escala 0.75 =====");

    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;

    wait (done);
    $display("DONE 0.75 en t=%0t", $time);
    $display("Ciclos: %0d  Lecturas: %0d  Escrituras: %0d",
             cycle_count, rd_count, wr_count);
    dump_output_to_hex("out_scale075.hex");

    //-----------------------------------------------------------------
    // 3) Escala 1.0
    //-----------------------------------------------------------------
    @(negedge clk);
    rst_n      = 1'b0;
    @(negedge clk);
    rst_n      = 1'b1;
    start      = 1'b0;

    scale_mode = 2'b00;  // 1.0
    $display("===== Probando escala 1.0 =====");

    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;

    wait (done);
    $display("DONE 1.0 en t=%0t", $time);
    $display("Ciclos: %0d  Lecturas: %0d  Escrituras: %0d",
             cycle_count, rd_count, wr_count);
    dump_output_to_hex("out_scale10.hex");

    //-----------------------------------------------------------------
    $display("======================================");
    $display("  Testbench controller_downscale_seq_tb TERMINADO");
    $display("======================================");
    $finish;
  end

endmodule
