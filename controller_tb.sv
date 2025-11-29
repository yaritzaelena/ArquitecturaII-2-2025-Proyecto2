`timescale 1ns/1ps
import interp_pkg::*;

module controller_tb;

    logic clk;
    logic rst_n;
    logic start;
    logic done;

    // Señal de stepping funcional
    logic allow_tick;

    // RAM ENTRADA
    logic                in_we;
    logic [18:0]         in_addr;
    logic [7:0]          in_wdata;
    logic [7:0]          in_rdata;

    // RAM SALIDA
    logic                out_we;
    logic [18:0]         out_addr;
    logic [7:0]          out_wdata;

    // Instancias RAM (igual que antes)
    ram_img #(
        .ADDR_WIDTH(19),
        .DATA_WIDTH(8)
    ) ram_in (
        .clk   (clk),
        .we    (in_we),
        .addr  (in_addr),
        .wdata (in_wdata),
        .rdata (in_rdata)
    );

    ram_img #(
        .ADDR_WIDTH(19),
        .DATA_WIDTH(8)
    ) ram_out (
        .clk   (clk),
        .we    (out_we),
        .addr  (out_addr),
        .wdata (out_wdata),
        .rdata ()
    );

    // DUT
    controller #(
        .LANES(4),
        .FRAC(FRAC_BITS),
        .IMG_W(512),     // Escalado a resolución real
        .IMG_H(512),
        .ADDR_W(19)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .allow_tick(allow_tick),
        .start     (start),
        .done      (done),
        .in_we     (in_we),
        .in_addr   (in_addr),
        .in_wdata  (in_wdata),
        .in_rdata  (in_rdata),
        .out_we    (out_we),
        .out_addr  (out_addr),
        .out_wdata (out_wdata)
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
        rst_n      = 0;
        start      = 0;
        allow_tick = 1'b1; // en este testbench se deja siempre habilitado

        inicializar_imagen();   // 512x512

        #20;
        rst_n = 1;

        #20;
        start = 1;
        #10;
        start = 0;

        wait(done);

        mostrar_resultados();

        #100;
        $finish;
    end

    // ====================================================
    // Tasks auxiliares (los mismos que ya tenías)
    // ====================================================
    task inicializar_imagen();
        integer i;
        for (i = 0; i < (1<<19); i++) begin
            ram_in.mem[i] = 8'(i % 256);
        end
    endtask

    task mostrar_resultados();
        integer i;
        $display("===== RAM OUTPUT (primeros 32 valores) =====");
        for (i = 0; i < 32; i++) begin
            $display("out[%0d] = %0d", i, ram_out.mem[i]);
        end
    endtask

endmodule



