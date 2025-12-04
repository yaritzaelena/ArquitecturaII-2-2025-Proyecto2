`timescale 1ns/1ps
import interp_pkg::*;

// ============================================================
// Testbench para controller.sv
// - Inicializa la RAM de entrada con una "imagen" de prueba
//   (gradiente simple).
// - Ejecuta el controlador con allow_tick siempre en 1 (sin stepping).
// - Espera a que done se ponga en 1.
// - Imprime los primeros valores de la RAM de salida.
// - Opcional: vuelca la RAM de salida a un archivo HEX.
// ============================================================

module controller_tb;

    // --------------------------------------------------------
    // Señales básicas
    // --------------------------------------------------------
    logic clk;
    logic rst_n;
    logic start;
    logic done;

    // Señal de stepping funcional (aquí la dejamos siempre en 1)
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
    // No necesitamos leer la RAM de salida en tiempo real, solo
    // su memoria interna al final de la simulación.

    // --------------------------------------------------------
    // Instancias de RAM (idénticas a las del top/controller)
    // --------------------------------------------------------
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
        .rdata ()          // no leemos en este testbench
    );

    // --------------------------------------------------------
    // DUT: controller (usa SIMD4 + interp_secuencial)
    // IMG_W/IMG_H = 512, ADDR_W = 19 (como en tu diseño)
    // --------------------------------------------------------
    controller #(
        .LANES (4),
        .FRAC  (FRAC_BITS),
        .IMG_W (512),
        .IMG_H (512),
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

    // --------------------------------------------------------
    // Reloj
    // --------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;   // periodo 10ns -> 100 MHz

    // --------------------------------------------------------
    // Estímulo principal
    // --------------------------------------------------------
    initial begin
        rst_n      = 0;
        start      = 0;
        allow_tick = 1'b1;   // aquí no usamos stepping, siempre puede avanzar

        // Inicializa la "imagen" de entrada antes de soltar el reset
        inicializar_imagen_gradiente();

        // Espera un poco y luego quita reset
        #20;
        rst_n = 1;

        // Espera un poco y lanza start (pulso)
        #20;
        start = 1;
        #10;
        start = 0;

        // Espera a que el controlador termine
        wait (done);

        // Muestra resultados en consola (primeros píxeles)
        mostrar_resultados();

        // Opcional: vuelca toda la RAM de salida a un archivo HEX
        volcar_salida_a_hex();

        #100;
        $finish;
    end

    // --------------------------------------------------------
    // Task: inicializar imagen de entrada
    //  - Aquí usamos un gradiente simple: mem[i] = i % 256
    //  - Eso se comporta como una "imagen sintética" de 512x512
    // --------------------------------------------------------
    task inicializar_imagen_gradiente();
        integer i;
        begin
            for (i = 0; i < (1<<19); i++) begin
                ram_in.mem[i] = 8'(i % 256);
            end
        end
    endtask

    // --------------------------------------------------------
    // Task: mostrar primeros valores de la RAM de salida
    //  - Útil para ver rápidamente si está escribiendo algo razonable
    // --------------------------------------------------------
    task mostrar_resultados();
        integer i;
        begin
            $display("===== RAM OUTPUT (primeros 64 valores) =====");
            for (i = 0; i < 64; i++) begin
                $display("out[%0d] = %0d", i, ram_out.mem[i]);
            end
        end
    endtask

    // --------------------------------------------------------
    // Task: volcar RAM de salida a un archivo HEX
    //  - Luego puedes abrir out_image.hex en Python/C y compararlo
    //    con una implementación de referencia en software.
    // --------------------------------------------------------
    task volcar_salida_a_hex();
        begin
            $display("Escribiendo RAM de salida a out_image.hex ...");
            $writememh("out_image.hex", ram_out.mem);
            $display("Listo.");
        end
    endtask

endmodule
