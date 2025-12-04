`timescale 1ns/1ps
import interp_pkg::*;

module controller_downscale_simd4_tb;

  // -------------------------------------------------------------
  // Parámetros de imagen
  // -------------------------------------------------------------
  localparam int FRAC   = FRAC_BITS;
  localparam int IMG_W  = 512;
  localparam int IMG_H  = 512;
  localparam int ADDR_W = 19;
  localparam int LANES  = 4;

  // Derivados por escala (solo para mensajes)
  localparam int OUT_W_05   = IMG_W/2;
  localparam int OUT_H_05   = IMG_H/2;
  localparam int OUT_W_075  = (IMG_W*3)/4;
  localparam int OUT_H_075  = (IMG_H*3)/4;
  localparam int OUT_W_10   = IMG_W;
  localparam int OUT_H_10   = IMG_H;

  // -------------------------------------------------------------
  // Señales globales
  // -------------------------------------------------------------
  logic clk;
  logic rst_n;
  logic allow_tick;

  // Selección de quién maneja la RAM de entrada
  typedef enum int {SEL_05 = 0, SEL_075 = 1, SEL_10 = 2} sel_t;
  sel_t active_sel;

  // -------------------------------------------------------------
  // Señales RAM entrada (compartida)
  // -------------------------------------------------------------
  logic              ram_in_we;
  logic [ADDR_W-1:0] ram_in_addr;
  logic [7:0]        ram_in_wdata;
  logic [7:0]        ram_in_rdata;

  // RAM entrada
  ram_img #(
      .ADDR_WIDTH(ADDR_W),
      .DATA_WIDTH(8)
  ) ram_in (
      .clk   (clk),
      .we    (ram_in_we),
      .addr  (ram_in_addr),
      .wdata (ram_in_wdata),
      .rdata (ram_in_rdata)
  );

  // -------------------------------------------------------------
  // RAMs de salida (una por escala)
  // -------------------------------------------------------------
  // 0.5
  logic              out05_we;
  logic [ADDR_W-1:0] out05_addr;
  logic [7:0]        out05_wdata;

  ram_img #(
      .ADDR_WIDTH(ADDR_W),
      .DATA_WIDTH(8)
  ) ram_out05 (
      .clk   (clk),
      .we    (out05_we),
      .addr  (out05_addr),
      .wdata (out05_wdata),
      .rdata ()
  );

  // 0.75
  logic              out075_we;
  logic [ADDR_W-1:0] out075_addr;
  logic [7:0]        out075_wdata;

  ram_img #(
      .ADDR_WIDTH(ADDR_W),
      .DATA_WIDTH(8)
  ) ram_out075 (
      .clk   (clk),
      .we    (out075_we),
      .addr  (out075_addr),
      .wdata (out075_wdata),
      .rdata ()
  );

  // 1.0
  logic              out10_we;
  logic [ADDR_W-1:0] out10_addr;
  logic [7:0]        out10_wdata;

  ram_img #(
      .ADDR_WIDTH(ADDR_W),
      .DATA_WIDTH(8)
  ) ram_out10 (
      .clk   (clk),
      .we    (out10_we),
      .addr  (out10_addr),
      .wdata (out10_wdata),
      .rdata ()
  );

  // -------------------------------------------------------------
  // DUT 0.5 (SCALE_NUM=1, SCALE_DEN=2)
  // -------------------------------------------------------------
  logic              start05, done05;
  logic              in05_we;
  logic [ADDR_W-1:0] in05_addr;
  logic [7:0]        in05_wdata;
  logic [7:0]        in05_rdata;
  logic [31:0]       cycle05, rd05, wr05;

  controller_downscale_simd4 #(
      .FRAC      (FRAC),
      .IMG_W     (IMG_W),
      .IMG_H     (IMG_H),
      .ADDR_W    (ADDR_W),
      .LANES     (LANES),
      .SCALE_NUM (1),
      .SCALE_DEN (2)
  ) dut05 (
      .clk        (clk),
      .rst_n      (rst_n),
      .allow_tick (allow_tick),
      .start      (start05),
      .done       (done05),

      .in_we      (in05_we),
      .in_addr    (in05_addr),
      .in_wdata   (in05_wdata),
      .in_rdata   (in05_rdata),

      .out_we     (out05_we),
      .out_addr   (out05_addr),
      .out_wdata  (out05_wdata),

      .cycle_count(cycle05),
      .rd_count   (rd05),
      .wr_count   (wr05)
  );

  // -------------------------------------------------------------
  // DUT 0.75 (SCALE_NUM=3, SCALE_DEN=4)
  // -------------------------------------------------------------
  logic              start075, done075;
  logic              in075_we;
  logic [ADDR_W-1:0] in075_addr;
  logic [7:0]        in075_wdata;
  logic [7:0]        in075_rdata;
  logic [31:0]       cycle075, rd075, wr075;

  controller_downscale_simd4 #(
      .FRAC      (FRAC),
      .IMG_W     (IMG_W),
      .IMG_H     (IMG_H),
      .ADDR_W    (ADDR_W),
      .LANES     (LANES),
      .SCALE_NUM (3),
      .SCALE_DEN (4)
  ) dut075 (
      .clk        (clk),
      .rst_n      (rst_n),
      .allow_tick (allow_tick),
      .start      (start075),
      .done       (done075),

      .in_we      (in075_we),
      .in_addr    (in075_addr),
      .in_wdata   (in075_wdata),
      .in_rdata   (in075_rdata),

      .out_we     (out075_we),
      .out_addr   (out075_addr),
      .out_wdata  (out075_wdata),

      .cycle_count(cycle075),
      .rd_count   (rd075),
      .wr_count   (wr075)
  );

  // -------------------------------------------------------------
  // DUT 1.0 (SCALE_NUM=1, SCALE_DEN=1)
  // -------------------------------------------------------------
  logic              start10, done10;
  logic              in10_we;
  logic [ADDR_W-1:0] in10_addr;
  logic [7:0]        in10_wdata;
  logic [7:0]        in10_rdata;
  logic [31:0]       cycle10, rd10, wr10;

  controller_downscale_simd4 #(
      .FRAC      (FRAC),
      .IMG_W     (IMG_W),
      .IMG_H     (IMG_H),
      .ADDR_W    (ADDR_W),
      .LANES     (LANES),
      .SCALE_NUM (1),
      .SCALE_DEN (1)
  ) dut10 (
      .clk        (clk),
      .rst_n      (rst_n),
      .allow_tick (allow_tick),
      .start      (start10),
      .done       (done10),

      .in_we      (in10_we),
      .in_addr    (in10_addr),
      .in_wdata   (in10_wdata),
      .in_rdata   (in10_rdata),

      .out_we     (out10_we),
      .out_addr   (out10_addr),
      .out_wdata  (out10_wdata),

      .cycle_count(cycle10),
      .rd_count   (rd10),
      .wr_count   (wr10)
  );

  // -------------------------------------------------------------
  // MUX de la RAM de entrada según active_sel
  // -------------------------------------------------------------
  // -------------------------------------------------------------
  // MUX de la RAM de entrada según active_sel
  // -------------------------------------------------------------
  // rdata compartido (todos ven lo mismo)
  assign in05_rdata  = ram_in_rdata;
  assign in075_rdata = ram_in_rdata;
  assign in10_rdata  = ram_in_rdata;

  always_comb begin
    // Valores por defecto
    ram_in_we    = 1'b0;
    ram_in_addr  = '0;
    ram_in_wdata = '0;

    case (active_sel)
      SEL_05: begin
        ram_in_we    = in05_we;
        ram_in_addr  = in05_addr;
        ram_in_wdata = in05_wdata;
      end

      SEL_075: begin
        ram_in_we    = in075_we;
        ram_in_addr  = in075_addr;
        ram_in_wdata = in075_wdata;
      end

      SEL_10: begin
        ram_in_we    = in10_we;
        ram_in_addr  = in10_addr;
        ram_in_wdata = in10_wdata;
      end

      default: begin
        // ya están en cero por los defaults
      end
    endcase
  end


  // -------------------------------------------------------------
  // Reloj
  // -------------------------------------------------------------
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // -------------------------------------------------------------
  // Secuencia de prueba
  // -------------------------------------------------------------
  integer i;

  initial begin
    // Init
    rst_n      = 1'b0;
    allow_tick = 1'b1;
    active_sel = SEL_05;

    start05 = 1'b0;
    start075 = 1'b0;
    start10 = 1'b0;

    // Cargar imagen
    $display("== Cargando cameraman_512x512.hex en ram_in ==");
    $readmemh("cameraman_512x512.hex", ram_in.mem);

    // Salir de reset
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    // =========================================================
    // 1) ESCALA 0.5
    // =========================================================
    $display("===== SIMD4 escala 0.5 (%0dx%0d) =====", OUT_W_05, OUT_H_05);
    active_sel = SEL_05;

    @(posedge clk);
    start05 <= 1'b1;
    @(posedge clk);
    start05 <= 1'b0;

    wait (done05);
    @(posedge clk);

    $display("DONE 0.5: cycles=%0d, rd=%0d, wr=%0d",
             cycle05, rd05, wr05);

    $display("Volcando salida 0.5 a out_simd4_05.hex");
    $writememh("out_simd4_05.hex", ram_out05.mem);

    // Reset para siguiente prueba
    @(posedge clk);
    rst_n = 1'b0;
    @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    // =========================================================
    // 2) ESCALA 0.75
    // =========================================================
    $display("===== SIMD4 escala 0.75 (%0dx%0d) =====", OUT_W_075, OUT_H_075);
    active_sel = SEL_075;

    @(posedge clk);
    start075 <= 1'b1;
    @(posedge clk);
    start075 <= 1'b0;

    wait (done075);
    @(posedge clk);

    $display("DONE 0.75: cycles=%0d, rd=%0d, wr=%0d",
             cycle075, rd075, wr075);

    $display("Volcando salida 0.75 a out_simd4_075.hex");
    $writememh("out_simd4_075.hex", ram_out075.mem);

    // Reset para siguiente prueba
    @(posedge clk);
    rst_n = 1'b0;
    @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    // =========================================================
    // 3) ESCALA 1.0
    // =========================================================
    $display("===== SIMD4 escala 1.0 (%0dx%0d) =====", OUT_W_10, OUT_H_10);
    active_sel = SEL_10;

    @(posedge clk);
    start10 <= 1'b1;
    @(posedge clk);
    start10 <= 1'b0;

    wait (done10);
    @(posedge clk);

    $display("DONE 1.0: cycles=%0d, rd=%0d, wr=%0d",
             cycle10, rd10, wr10);

    $display("Volcando salida 1.0 a out_simd4_10.hex");
    $writememh("out_simd4_10.hex", ram_out10.mem);

    // Fin
    $display("======================================");
    $display("  TB SIMD4 TERMINADO (3 escalas)     ");
    $display("======================================");
    $finish;
  end

endmodule
