`timescale 1ns/1ps
import interp_pkg::*;

module controller_step_tb;

    // =======================
    // Señales
    // =======================
    logic clk;
    logic rst_n;
    logic start;
    logic done;
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

    int step_i;  // contador de pasos

    // =======================
    // Instancias RAM
    // =======================
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

    // =======================
    // DUT: controller
    // =======================
    controller #(
        .LANES (4),
        .FRAC  (FRAC_BITS),
        .IMG_W (8),      // pequeño para ver fácil el stepping
        .IMG_H (8),
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

    // =======================
    // Clock
    // =======================
    initial clk = 0;
    always #5 clk = ~clk;   // 100 MHz

    // =======================
    // Inicializar imagen
    // =======================
    task inicializar_imagen();
        integer i;
        begin
            for (i = 0; i < (1<<19); i++) begin
                ram_in.mem[i] = 8'(i % 256);
            end
        end
    endtask

    // =======================
    // Task de debug
    // =======================
    task print_debug(input string label);
        $display("[%s] state=%0d x_block=%0d y_block=%0d load_cnt=%0d lane_wr_idx=%0d done=%0b",
                 label,
                 dut.state,
                 dut.x_block,
                 dut.y_block,
                 dut.load_cnt,
                 dut.lane_wr_idx,
                 done);
    endtask

    // =======================
    // STEP automático cuando allow_tick=1
    // =======================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            step_i <= 0;
        end else if (allow_tick) begin
            step_i <= step_i + 1;
            print_debug($sformatf("STEP %0d", step_i));
        end
    end

    // =======================
    // Estímulo base
    // =======================
    initial begin
        rst_n      = 0;
        start      = 0;
        allow_tick = 0;
        // OJO: ya NO tocamos step_i aquí

        inicializar_imagen();

        #50;
        rst_n = 1;  // salir de reset

        // 1 ciclo: start=1 y allow_tick=1 para salir de S_IDLE
        @(negedge clk);
        start      <= 1;
        allow_tick <= 1;

        @(negedge clk);
        start      <= 0;
        allow_tick <= 0;

        // Imprimir estado inicial después del "arranque"
        print_debug("AFTER_INIT");
    end

endmodule



