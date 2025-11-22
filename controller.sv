// ===============================================================
// controller.sv
// Controlador SIMD con RAM síncrona (1 ciclo de latencia)
// FSM corregida con estados separados de ADDR/DATA para LOAD_TOP y LOAD_BOTTOM
// ===============================================================

`timescale 1ns/1ps
import interp_pkg::*;

module controller #(
    parameter int LANES      = 4,
    parameter int FRAC       = FRAC_BITS,
    parameter int IMG_W      = 8,     // para depuración rápida (luego 512)
    parameter int IMG_H      = 8,
    parameter int ADDR_W     = 19
)(
    input  logic              clk,
    input  logic              rst_n,

    input  logic              start,
    output logic              done,

    // RAM de entrada (solo lectura)
    output logic              in_we,
    output logic [ADDR_W-1:0] in_addr,
    output logic [7:0]        in_wdata,
    input  logic [7:0]        in_rdata,

    // RAM de salida (solo escritura)
    output logic              out_we,
    output logic [ADDR_W-1:0] out_addr,
    output logic [7:0]        out_wdata
);

    // ===============================================================
    // 1. SIMD registers
    // ===============================================================
    logic [7:0] p00_vec[LANES];
    logic [7:0] p10_vec[LANES];
    logic [7:0] p01_vec[LANES];
    logic [7:0] p11_vec[LANES];

    logic [FRAC-1:0] fx_vec[LANES];
    logic [FRAC-1:0] fy_vec[LANES];

    logic [7:0] pixel_out_vec[LANES];
    logic       valid_in_simd;
    logic       valid_out_simd;

    // Por ahora: fx = fy = 0.0
    localparam logic [FRAC-1:0] FX_CONST = '0;
    localparam logic [FRAC-1:0] FY_CONST = '0;

    // ===============================================================
    // 2. Instancia del bloque SIMD
    // ===============================================================
    interp_simd4 #(
        .LANES(LANES),
        .FRAC(FRAC)
    ) u_simd4 (
        .clk          (clk),
        .rst_n        (rst_n),
        .valid_in     (valid_in_simd),
        .p00_vec      (p00_vec),
        .p10_vec      (p10_vec),
        .p01_vec      (p01_vec),
        .p11_vec      (p11_vec),
        .fx_vec       (fx_vec),
        .fy_vec       (fy_vec),
        .pixel_out_vec(pixel_out_vec),
        .valid_out    (valid_out_simd)
    );

    // ===============================================================
    // 3. FSM
    // ===============================================================
    typedef enum logic [3:0] {
        S_IDLE,
        S_LOAD_TOP_ADDR,
        S_LOAD_TOP_DATA,
        S_LOAD_BOTTOM_ADDR,
        S_LOAD_BOTTOM_DATA,
        S_COMPUTE,
        S_WRITE,
        S_NEXT,
        S_DONE
    } state_t;

    state_t state, next_state;

    localparam int BLOCKS_X = IMG_W / LANES;

    logic [$clog2(BLOCKS_X)-1:0] x_block;     // bloque horizontal
    logic [$clog2(IMG_H)-1:0]    y_block;     // fila de salida

    // 0..(2*LANES-1): para leer p00/p10 o p01/p11
    logic [$clog2(2*LANES)-1:0]  load_cnt;

    // 0..(LANES-1): para escribir pixel_out_vec
    logic [$clog2(LANES)-1:0]    lane_wr_idx;

    // ===============================================================
    // 4. Cálculo de direcciones de vecinos
    // ===============================================================
    logic [ADDR_W-1:0] addr_p00_vec[LANES];
    logic [ADDR_W-1:0] addr_p10_vec[LANES];
    logic [ADDR_W-1:0] addr_p01_vec[LANES];
    logic [ADDR_W-1:0] addr_p11_vec[LANES];

    integer k;

    always_comb begin
        for (k = 0; k < LANES; k = k + 1) begin
            logic [ADDR_W-1:0] x_pix;
            logic [ADDR_W-1:0] y_pix;
            logic [ADDR_W-1:0] x0, x1, y0, y1;

            // Coordenadas de salida del lane k
            x_pix = x_block*LANES + k;
            y_pix = y_block;

            x0 = x_pix;
            x1 = x_pix + 1;
            y0 = y_pix;
            y1 = y_pix + 1;

            addr_p00_vec[k] = y0*IMG_W + x0;
            addr_p10_vec[k] = y0*IMG_W + x1;
            addr_p01_vec[k] = y1*IMG_W + x0;
            addr_p11_vec[k] = y1*IMG_W + x1;

            fx_vec[k] = FX_CONST;
            fy_vec[k] = FY_CONST;
        end
    end

    // ===============================================================
    // 5. Registro de estado y contadores
    // ===============================================================
    integer i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            x_block     <= '0;
            y_block     <= '0;
            load_cnt    <= '0;
            lane_wr_idx <= '0;

            for (i = 0; i < LANES; i = i + 1) begin
                p00_vec[i] <= '0;
                p10_vec[i] <= '0;
                p01_vec[i] <= '0;
                p11_vec[i] <= '0;
            end

        end else begin
            state <= next_state;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        x_block     <= '0;
                        y_block     <= '0;
                        load_cnt    <= '0;
                        lane_wr_idx <= '0;
                    end
                end

                // ============================
                // TOP ROW: capturar datos
                // ============================
                S_LOAD_TOP_ADDR: begin
                    // nada; solo se usa load_cnt tal cual
                end

                S_LOAD_TOP_DATA: begin
                    // in_rdata corresponde a la dirección emitida en S_LOAD_TOP_ADDR
                    if (load_cnt < LANES)
                        p00_vec[load_cnt] <= in_rdata;
                    else
                        p10_vec[load_cnt-LANES] <= in_rdata;

                    if (load_cnt == 2*LANES-1)
                        load_cnt <= '0;
                    else
                        load_cnt <= load_cnt + 1;
                end

                // ============================
                // BOTTOM ROW: capturar datos
                // ============================
                S_LOAD_BOTTOM_ADDR: begin
                    // nada; solo se usa load_cnt tal cual
                end

                S_LOAD_BOTTOM_DATA: begin
                    if (load_cnt < LANES)
                        p01_vec[load_cnt] <= in_rdata;
                    else
                        p11_vec[load_cnt-LANES] <= in_rdata;

                    if (load_cnt == 2*LANES-1)
                        load_cnt <= '0;
                    else
                        load_cnt <= load_cnt + 1;
                end

                // ============================
                // Escritura de resultados
                // ============================
                S_WRITE: begin
                    if (lane_wr_idx == LANES-1)
                        lane_wr_idx <= '0;
                    else
                        lane_wr_idx <= lane_wr_idx + 1;
                end

                // ============================
                // Avance de bloques
                // ============================
                S_NEXT: begin
                    if (x_block == BLOCKS_X-1) begin
                        x_block <= '0;
                        if (y_block == IMG_H-2)
                            y_block <= '0;
                        else
                            y_block <= y_block + 1;
                    end else begin
                        x_block <= x_block + 1;
                    end
                end

                default: ;
            endcase
        end
    end

    // ===============================================================
    // 6. Lógica combinacional de la FSM
    // ===============================================================
    logic [ADDR_W-1:0] x_out_lane_wr;
    logic [ADDR_W-1:0] y_out_wr;

    always_comb begin
        // valores por defecto
        next_state    = state;
        done          = 1'b0;

        in_we         = 1'b0;
        in_addr       = '0;
        in_wdata      = '0;

        out_we        = 1'b0;
        out_addr      = '0;
        out_wdata     = '0;

        valid_in_simd = 1'b0;

        case (state)
            // ------------------------
            // IDLE
            // ------------------------
            S_IDLE: begin
                if (start)
                    next_state = S_LOAD_TOP_ADDR;
            end

            // ------------------------
            // LOAD TOP (ADDR/DATA)
            // ------------------------
            S_LOAD_TOP_ADDR: begin
                // emitir dirección para p00/p10
                in_we = 1'b0;
                if (load_cnt < LANES)
                    in_addr = addr_p00_vec[load_cnt];
                else
                    in_addr = addr_p10_vec[load_cnt-LANES];

                next_state = S_LOAD_TOP_DATA;
            end

            S_LOAD_TOP_DATA: begin
                // aquí se captura in_rdata (en always_ff)
                if (load_cnt == 2*LANES-1)
                    next_state = S_LOAD_BOTTOM_ADDR;
                else
                    next_state = S_LOAD_TOP_ADDR;
            end

            // ------------------------
            // LOAD BOTTOM (ADDR/DATA)
            // ------------------------
            S_LOAD_BOTTOM_ADDR: begin
                in_we = 1'b0;
                if (load_cnt < LANES)
                    in_addr = addr_p01_vec[load_cnt];
                else
                    in_addr = addr_p11_vec[load_cnt-LANES];

                next_state = S_LOAD_BOTTOM_DATA;
            end

            S_LOAD_BOTTOM_DATA: begin
                if (load_cnt == 2*LANES-1)
                    next_state = S_COMPUTE;
                else
                    next_state = S_LOAD_BOTTOM_ADDR;
            end

            // ------------------------
            // COMPUTE
            // ------------------------
            S_COMPUTE: begin
                valid_in_simd = 1'b1;   // pulso de un ciclo
                next_state    = S_WRITE;
            end

            // ------------------------
            // WRITE: escribir los LANES
            // ------------------------
            S_WRITE: begin
                out_we = 1'b1;

                x_out_lane_wr = x_block*LANES + lane_wr_idx;
                y_out_wr      = y_block;

                out_addr  = y_out_wr*IMG_W + x_out_lane_wr;
                out_wdata = pixel_out_vec[lane_wr_idx];

                if (lane_wr_idx == LANES-1)
                    next_state = S_NEXT;
            end

            // ------------------------
            // NEXT: avanzar bloque/fila
            // ------------------------
            S_NEXT: begin
                if ((x_block == BLOCKS_X-1) && (y_block == IMG_H-2))
                    next_state = S_DONE;
                else
                    next_state = S_LOAD_TOP_ADDR;
            end

            // ------------------------
            // DONE
            // ------------------------
            S_DONE: begin
                done = 1'b1;
                if (!start)
                    next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

endmodule


