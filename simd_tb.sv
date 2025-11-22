`timescale 1ns/1ps

module simd_tb;

    // Parámetros
    localparam int N            = 4;
    localparam int PIXEL_W      = 8;
    localparam int COEFF_W      = 16;
    localparam int FRAC_W       = 8;
    localparam int ACC_W        = PIXEL_W + COEFF_W + 2;
    localparam int TOTAL_BLOCKS = 16;

    // Señales
    logic clk;
    logic rst;
    logic load;

    logic [PIXEL_W-1:0] p00 [N-1:0];
    logic [PIXEL_W-1:0] p01 [N-1:0];
    logic [PIXEL_W-1:0] p10 [N-1:0];
    logic [PIXEL_W-1:0] p11 [N-1:0];

    logic [COEFF_W-1:0] w00 [N-1:0];
    logic [COEFF_W-1:0] w01 [N-1:0];
    logic [COEFF_W-1:0] w10 [N-1:0];
    logic [COEFF_W-1:0] w11 [N-1:0];

    logic [PIXEL_W-1:0] out_pix   [N-1:0];
    logic [PIXEL_W-1:0] expected  [N-1:0];

    // Variables obligatoriamente al inicio (por ModelSim antiguo)
    integer cycle_count;
    logic   count_enable;
    integer i;
    integer b;
    integer total_pixels;
    real    cycles_per_pixel;

    // Instancia de SIMD TOP
    simd_top #(
        .N       (N),
        .PIXEL_W (PIXEL_W),
        .FRAC_W  (FRAC_W),
        .COEFF_W (COEFF_W),
        .ACC_W   (ACC_W)
    ) dut (
        .clk    (clk),
        .rst    (rst),
        .load   (load),
        .p00    (p00),
        .p01    (p01),
        .p10    (p10),
        .p11    (p11),
        .w00    (w00),
        .w01    (w01),
        .w10    (w10),
        .w11    (w11),
        .out_pix(out_pix)
    );

    // Reloj
    always #5 clk = ~clk;

    // Contador de ciclos
    always @(posedge clk or posedge rst) begin
        if (rst)
            cycle_count <= 0;
        else if (count_enable)
            cycle_count <= cycle_count + 1;
    end

    // Función de referencia (misma interpolación)
    function automatic [PIXEL_W-1:0] bilinear_ref(
        input [PIXEL_W-1:0] fp00,
        input [PIXEL_W-1:0] fp01,
        input [PIXEL_W-1:0] fp10,
        input [PIXEL_W-1:0] fp11,
        input [COEFF_W-1:0] fw00,
        input [COEFF_W-1:0] fw01,
        input [COEFF_W-1:0] fw10,
        input [COEFF_W-1:0] fw11
    );
        reg [31:0] m00, m01, m10, m11;
        reg [31:0] acc, shifted;
        begin
            m00 = fp00 * fw00;
            m01 = fp01 * fw01;
            m10 = fp10 * fw10;
            m11 = fp11 * fw11;
            acc = m00 + m01 + m10 + m11;
            shifted = acc >> FRAC_W;
            bilinear_ref = (shifted > 255) ? 8'd255 : shifted[7:0];
        end
    endfunction

    // ==================================================
    // TEST COMPLETO
    // ==================================================
    initial begin
        
        // Inicialización
        clk          = 0;
        rst          = 1;
        load         = 0;
        count_enable = 0;

        for (i=0; i<N; i++) begin
            p00[i]=0; p01[i]=0; p10[i]=0; p11[i]=0;
            w00[i]=0; w01[i]=0; w10[i]=0; w11[i]=0;
        end

        // Reset
        #20;
        rst = 0;

        // ================================
        // 1?? TEST (expected vs out)
        // ================================
        $display("===== TEST SIMD =====");

        // Datos ejemplo reales
        p00[0]=10;  p01[0]=20;  p10[0]=30;  p11[0]=40;
        p00[1]=50;  p01[1]=60;  p10[1]=70;  p11[1]=80;
        p00[2]=100; p01[2]=110; p10[2]=120; p11[2]=130;
        p00[3]=200; p01[3]=210; p10[3]=220; p11[3]=230;

        // Pesos que suman 256
        w00[0]=192; w01[0]=32;  w10[0]=16;  w11[0]=16;
        w00[1]=64;  w01[1]=64;  w10[1]=64;  w11[1]=64;
        w00[2]=128; w01[2]=64;  w10[2]=32;  w11[2]=32;
        w00[3]=16;  w01[3]=80;  w10[3]=80;  w11[3]=80;

        // LOAD
        @(posedge clk) load = 1;
        @(posedge clk) load = 0;

        // Esperar resultados
        repeat (4) @(posedge clk);

        // Comparación con expected
        for (i=0; i<N; i++) begin
            expected[i] = bilinear_ref(
                p00[i], p01[i], p10[i], p11[i],
                w00[i], w01[i], w10[i], w11[i]
            );

            $display("Lane %0d: expected=%0d  out_pix=%0d",
                      i, expected[i], out_pix[i]);

            if (expected[i] !== out_pix[i])
                $display("  >>> MISMATCH <<<");
            else
                $display("  OK");
        end

        // =======================
        // 2?? RENDIMIENTO SIMD
        // =======================
        $display("\n===== RENDIMIENTO SIMD =====");

        // Pesos se mantienen, vecinos cambian por bloque
        count_enable = 0;

        for (b=0; b<TOTAL_BLOCKS; b++) begin
            p00[0]=8'(10  + b); p01[0]=8'(20  + b);
            p10[0]=8'(30  + b); p11[0]=8'(40  + b);

            p00[1]=8'(50  + b); p01[1]=8'(60  + b);
            p10[1]=8'(70  + b); p11[1]=8'(80  + b);

            p00[2]=8'(100 + b); p01[2]=8'(110 + b);
            p10[2]=8'(120 + b); p11[2]=8'(130 + b);

            p00[3]=8'(200 + b); p01[3]=8'(210 + b);
            p10[3]=8'(220 + b); p11[3]=8'(230 + b);

            @(posedge clk);
            load <= 1;

            if (b==0)
                count_enable <= 1;

            @(posedge clk);
            load <= 0;
        end

        // Vaciar pipeline
        repeat (4) @(posedge clk);
        count_enable = 0;

        // Resultados
        total_pixels     = TOTAL_BLOCKS * N;
        cycles_per_pixel = cycle_count * 1.0 / total_pixels;

        $display("Pixeles totales         = %0d", total_pixels);
        $display("Ciclos totales (SIMD)   = %0d", cycle_count);
        $display("Ciclos por pixel (SIMD) = %0f", cycles_per_pixel);

        #20;
        $finish;
    end

endmodule

