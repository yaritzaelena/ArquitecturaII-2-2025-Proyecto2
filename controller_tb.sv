`timescale 1ns/1ps
import interp_pkg::*;

module controller_tb;


    logic clk;
    logic rst_n;
    logic start;
    logic done;

    // RAM ENTRADA
    logic                in_we;
    logic [18:0]         in_addr;     // 19 bits para 512*512
    logic [7:0]          in_wdata;
    logic [7:0]          in_rdata;

    // RAM SALIDA
    logic                out_we;
    logic [18:0]         out_addr;    // 19 bits
    logic [7:0]          out_wdata;

    // ====================================================
    // Instancias
    // ====================================================

    // RAM de entrada (imagen original)
    ram_img #(
        .ADDR_WIDTH(19),
        .DATA_WIDTH(8)
    ) ram_in (
        .clk    (clk),
        .we     (in_we),
        .addr   (in_addr),
        .wdata  (in_wdata),
        .rdata  (in_rdata)
    );

    // RAM de salida (imagen resultante)
    ram_img #(
        .ADDR_WIDTH(19),
        .DATA_WIDTH(8)
    ) ram_out (
        .clk    (clk),
        .we     (out_we),
        .addr   (out_addr),
        .wdata  (out_wdata),
        .rdata  ()     // no necesitamos leerla en TB
    );

    // Controller
    controller #(
        .LANES(4),
        .FRAC(FRAC_BITS),
        .IMG_W(512),
        .IMG_H(512),
        .ADDR_W(19)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .done(done),
        .in_we(in_we),
        .in_addr(in_addr),
        .in_wdata(in_wdata),
        .in_rdata(in_rdata),
        .out_we(out_we),
        .out_addr(out_addr),
        .out_wdata(out_wdata)
    );


    initial clk = 0;
    always #5 clk = ~clk;   // 100 MHz


    // Estímulo

    initial begin
        // Inicialización
        rst_n = 0;
        start = 0;
        in_we = 0;
        in_addr = 0;
        in_wdata = 0;

        // Pre-cargar RAM de entrada ANTES del reset
        inicializar_imagen();

        #20;
        rst_n = 1;      // liberar reset

        #50;
        start = 1;      // dar pulso de start
        #10;
        start = 0;

        // Esperar a que termine
        wait (done == 1);

        #100;
        $display("===== SIMULACIÓN COMPLETA =====");
        $stop;
    end

    // ====================================================
    // Inicialización de RAM (imagen patrón)
    // ====================================================
    task inicializar_imagen();
        integer i;
        for (i = 0; i < 512*512; i = i + 1) begin
            ram_in.mem[i] = i % 256;   // patrón simple: 0,1,2,...255,0,1,...
        end
    endtask

endmodule
