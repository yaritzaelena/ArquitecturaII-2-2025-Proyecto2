`timescale 1ns/1ps
import interp_pkg::*;

module controller_tb;

    logic clk;
    logic rst_n;
    logic start;
    logic done;

    // RAM ENTRADA
    logic                in_we;
    logic [18:0]         in_addr;
    logic [7:0]          in_wdata;
    logic [7:0]          in_rdata;

    // RAM SALIDA
    logic                out_we;
    logic [18:0]         out_addr;
    logic [7:0]          out_wdata;

    // ====================================================
    // RAM de entrada
    // ====================================================
    ram_img #(
        .ADDR_WIDTH(19),
        .DATA_WIDTH(8)
    ) ram_in (
        .clk    (clk),
        .we     (in_we),      // Solo controller lo maneja
        .addr   (in_addr),
        .wdata  (in_wdata),
        .rdata  (in_rdata)
    );

    // ====================================================
    // RAM de salida
    // ====================================================
    ram_img #(
        .ADDR_WIDTH(19),
        .DATA_WIDTH(8)
    ) ram_out (
        .clk    (clk),
        .we     (out_we),     // Solo controller lo maneja
        .addr   (out_addr),
        .wdata  (out_wdata),
        .rdata  ()
    );

    // ====================================================
    // Controller
    // ====================================================
    controller #(
        .LANES(4),
        .FRAC(FRAC_BITS),
        .IMG_W(512),     // Escalado a resolución real
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

    // ====================================================
    // Clock
    // ====================================================
    initial clk = 0;
    always #5 clk = ~clk;   // 100 MHz

    // ====================================================
    // Estímulo principal
    // ====================================================
    initial begin
        rst_n = 0;
        start = 0;

        inicializar_imagen();   // 512x512

        #20;
        rst_n = 1;

        #20;
        start = 1;
        #10;
        start = 0;

        // Esperar a que termine
        wait (done == 1);

        #20;
        mostrar_resultados();

        $display("===== SIMULACIÓN COMPLETA =====");
        $stop;
    end

    // ====================================================
    // Inicializar RAM de entrada 512x512
    // ====================================================
    task inicializar_imagen();
        integer i;
        for (i = 0; i < 512*512; i++) begin
            ram_in.mem[i] = i % 256;   // patrón simple
        end
    endtask

    // ====================================================
    // Mostrar primeros valores de salida
    // ====================================================
    task mostrar_resultados();
        integer i;
        $display("===== RAM OUTPUT (primeros 32 valores) =====");
        for (i = 0; i < 32; i++) begin
            $display("out[%0d] = %0d", i, ram_out.mem[i]);
        end
    endtask

endmodule


