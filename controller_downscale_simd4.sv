// ===============================================================
// controller_downscale_simd4.sv  (VERSION GENERALIZADA)
//
// Controlador SIMD (4 lanes) para downscaling con interpolación bilineal.
//
// - Procesa LANES píxeles de salida por grupo usando interp_simd4.
// - Entrada: imagen IMG_W x IMG_H en RAM de entrada (ram_img).
// - Salida: imagen OUT_W x OUT_H en RAM de salida (ram_img).
// - Factor de escala = SCALE_NUM / SCALE_DEN (0.5 – 1.0 típicamente).
// - Coordinadas fuente en Q0.FRAC calculadas igual que en la versión
//   secuencial: src = (x_out + 0.5) * step, donde
//     step = (SCALE_DEN * ONE_Q) / SCALE_NUM = 1/escala.
//
// - Stepping controlado por allow_tick.
// - Contadores de ciclos, lecturas y escrituras.
// ===============================================================

`timescale 1ns/1ps
import interp_pkg::*;

module controller_downscale_simd4 #(
    parameter int FRAC       = FRAC_BITS,
    parameter int IMG_W      = 512,
    parameter int IMG_H      = 512,
    parameter int ADDR_W     = 19,
    parameter int LANES      = 4,

    // Factor de escala = SCALE_NUM / SCALE_DEN (0.5 – 1.0)
    parameter int SCALE_NUM  = 1,
    parameter int SCALE_DEN  = 1
)(
    input  logic              clk,
    input  logic              rst_n,

    input  logic              allow_tick,   // stepping
    input  logic              start,
    output logic              done,

    // RAM de entrada
    output logic              in_we,
    output logic [ADDR_W-1:0] in_addr,
    output logic [7:0]        in_wdata,
    input  logic [7:0]        in_rdata,

    // RAM de salida
    output logic              out_we,
    output logic [ADDR_W-1:0] out_addr,
    output logic [7:0]        out_wdata,

    // Performance counters
    output logic [31:0]       cycle_count,
    output logic [31:0]       rd_count,
    output logic [31:0]       wr_count
);

    // ===========================================================
    // Parámetros derivados
    // ===========================================================
    localparam int ONE_Q    = 1 << FRAC;

    // Tamaño de salida según factor de escala
    localparam int OUT_W    = (IMG_W * SCALE_NUM) / SCALE_DEN;
    localparam int OUT_H    = (IMG_H * SCALE_NUM) / SCALE_DEN;

    // Paso en coordenadas fuente (cuánto avanzamos en la imagen fuente
    // cuando avanzamos 1 píxel en la imagen de salida):
    //
    //   escala = SCALE_NUM / SCALE_DEN
    //   step   = 1 / escala = SCALE_DEN / SCALE_NUM
    //
    // Representado en Q0.FRAC:
    //   STEP_Q = (SCALE_DEN * ONE_Q) / SCALE_NUM
    localparam int STEP_X_Q = (SCALE_DEN * ONE_Q) / SCALE_NUM;
    localparam int STEP_Y_Q = (SCALE_DEN * ONE_Q) / SCALE_NUM;

    // ===========================================================
    // Señales hacia interp_simd4
    // ===========================================================
    logic        v_valid_in;
    logic        v_valid_out;

    u8_t         v_p00   [LANES];
    u8_t         v_p10   [LANES];
    u8_t         v_p01   [LANES];
    u8_t         v_p11   [LANES];

    logic [FRAC-1:0] v_fx[LANES];
    logic [FRAC-1:0] v_fy[LANES];

    u8_t         v_pixel_out[LANES];

    // Núcleo SIMD de interpolación
    interp_simd4 #(
        .LANES (LANES),
        .FRAC  (FRAC)
    ) u_interp_simd4 (
        .clk           (clk),
        .rst_n         (rst_n),
        .valid_in      (v_valid_in),

        .p00_vec       (v_p00),
        .p10_vec       (v_p10),
        .p01_vec       (v_p01),
        .p11_vec       (v_p11),
        .fx_vec        (v_fx),
        .fy_vec        (v_fy),

        .valid_out     (v_valid_out),
        .pixel_out_vec (v_pixel_out)
    );

    // Como nunca escribimos en la RAM de entrada, amarramos esto a 0.
    assign in_we    = 1'b0;
    assign in_wdata = 8'd0;

    // ===========================================================
    // FSM principal
    // ===========================================================
    typedef enum logic [3:0] {
        S_IDLE,
        S_SETUP_GROUP,       // prepara coordenadas de LANES píxeles destino
        S_READ_NEIGH_ADDR,   // seleccionar vecino y lane para lectura
        S_READ_NEIGH_DATA,   // capturar dato desde RAM
        S_INTERP_START,      // lanzar SIMD
        S_INTERP_WAIT,       // esperar valid_out
        S_WRITE_GROUP,       // escribir hasta LANES píxeles
        S_NEXT_GROUP,        // avanzar x,y
        S_DONE
    } state_t;

    state_t state, next_state;

    // Coordenadas destino base del grupo
    int unsigned x_base;        // x del lane 0 en la fila actual
    int unsigned y_out;

    // Coordenadas fuente por lane (Q0.FRAC)
    logic [31:0] src_x_q [LANES];
    logic [31:0] src_y_q [LANES];

    // Coordenadas de píxel entero + fracciones por lane
    int unsigned      x0_lane [LANES];
    int unsigned      y0_lane [LANES];
    logic [FRAC-1:0]  fx_lane [LANES];
    logic [FRAC-1:0]  fy_lane [LANES];

    // Vecinos leídos de RAM por lane
    u8_t p00_lane [LANES];
    u8_t p10_lane [LANES];
    u8_t p01_lane [LANES];
    u8_t p11_lane [LANES];

    // Índices para lectura de vecinos y escritura
    int unsigned lane_idx;      // 0..LANES-1
    int unsigned neigh_idx;     // 0..3 (p00,p10,p01,p11)
    int unsigned write_idx;     // 0..LANES-1 (escritura de resultados)

    // Lanes activos (por si OUT_W no es múltiplo de LANES)
    logic lane_active[LANES];

    // Variables temporales
    int unsigned i;
    int unsigned x_lane_tmp;
    int unsigned x0_tmp, y0_tmp;
    logic [FRAC-1:0] fx_tmp, fy_tmp;
    logic [ADDR_W-1:0] addr_tmp;
    int unsigned x_lane_write;
    int unsigned y_next;

    // ===========================================================
    // FSM combinacional (NO toca out_we/out_wdata)
    // ===========================================================
    always_comb begin
        v_valid_in = 1'b0;
        next_state = state;
        done       = (state == S_DONE);

        case (state)
            S_IDLE: begin
                if (start)
                    next_state = S_SETUP_GROUP;
            end

            S_SETUP_GROUP: begin
                next_state = S_READ_NEIGH_ADDR;
            end

            S_READ_NEIGH_ADDR: begin
                next_state = S_READ_NEIGH_DATA;
            end

            S_READ_NEIGH_DATA: begin
                // 16 lecturas: 4 vecinos x LANES
                if ((lane_idx == LANES-1) && (neigh_idx == 3))
                    next_state = S_INTERP_START;
                else
                    next_state = S_READ_NEIGH_ADDR;
            end

            S_INTERP_START: begin
                v_valid_in = 1'b1;
                next_state = S_INTERP_WAIT;
            end

            S_INTERP_WAIT: begin
                if (v_valid_out)
                    next_state = S_WRITE_GROUP;
            end

            S_WRITE_GROUP: begin
                if (write_idx == LANES-1)
                    next_state = S_NEXT_GROUP;
            end

            S_NEXT_GROUP: begin
                // ¿Hemos llegado al final de la imagen de salida?
                if ( (y_out == OUT_H-1) && (x_base + LANES >= OUT_W) )
                    next_state = S_DONE;
                else
                    next_state = S_SETUP_GROUP;
            end

            S_DONE: begin
                if (!start)
                    next_state = S_IDLE;
            end

            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

    // ===========================================================
    // Secuencial: estado, coordenadas, direcciones, contadores
    // ===========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            x_base      <= 0;
            y_out       <= 0;
            lane_idx    <= 0;
            neigh_idx   <= 0;
            write_idx   <= 0;
            in_addr     <= '0;
            out_addr    <= '0;

            cycle_count <= 32'd0;
            rd_count    <= 32'd0;
            wr_count    <= 32'd0;

            out_we      <= 1'b0;
            out_wdata   <= 8'd0;

            for (i = 0; i < LANES; i = i + 1) begin
                src_x_q[i]    <= '0;
                src_y_q[i]    <= '0;
                x0_lane[i]    <= '0;
                y0_lane[i]    <= '0;
                fx_lane[i]    <= '0;
                fy_lane[i]    <= '0;
                p00_lane[i]   <= '0;
                p10_lane[i]   <= '0;
                p01_lane[i]   <= '0;
                p11_lane[i]   <= '0;
                lane_active[i]<= 1'b0;
                v_p00[i]      <= '0;
                v_p10[i]      <= '0;
                v_p01[i]      <= '0;
                v_p11[i]      <= '0;
                v_fx[i]       <= '0;
                v_fy[i]       <= '0;
            end
        end
        else begin
            if (!allow_tick) begin
                // Pausa por stepping
                state <= state;
            end
            else begin
                state <= next_state;

                // Default de escritura
                out_we    <= 1'b0;
                out_wdata <= 8'd0;

                // Contador de ciclos
                if (state != S_DONE)
                    cycle_count <= cycle_count + 1;

                case (state)

                    // -----------------------------------------
                    // INICIO
                    // -----------------------------------------
                    S_IDLE: begin
                        if (start) begin
                            x_base    <= 0;
                            y_out     <= 0;
                            lane_idx  <= 0;
                            neigh_idx <= 0;
                            write_idx <= 0;

                            cycle_count <= 32'd0;
                            rd_count    <= 32'd0;
                            wr_count    <= 32'd0;
                        end
                    end

                    // -----------------------------------------
                    // PREPARAR GRUPO DE LANES
                    // -----------------------------------------
                    S_SETUP_GROUP: begin
                        for (i = 0; i < LANES; i = i + 1) begin
                            x_lane_tmp     = x_base + i;
                            lane_active[i] <= (x_lane_tmp < OUT_W);

                            // Coordenada fuente en Q0.FRAC:
                            //   src = (x + 0.5) * STEP_X_Q
                            //   src = (y + 0.5) * STEP_Y_Q
                            src_x_q[i] <= (x_lane_tmp * STEP_X_Q) + (STEP_X_Q >> 1);
                            src_y_q[i] <= (y_out      * STEP_Y_Q) + (STEP_Y_Q >> 1);
                        end

                        lane_idx  <= 0;
                        neigh_idx <= 0;
                    end

                    // -----------------------------------------
                    // LECTURA DE VECINOS (dirección)
                    // -----------------------------------------
                    S_READ_NEIGH_ADDR: begin
                        // Para neigh_idx == 0 calculamos x0,y0,fx,fy para el lane actual
                        if (neigh_idx == 0) begin
                            x0_tmp = src_x_q[lane_idx] >> FRAC;
                            y0_tmp = src_y_q[lane_idx] >> FRAC;
                            fx_tmp = src_x_q[lane_idx][FRAC-1:0];
                            fy_tmp = src_y_q[lane_idx][FRAC-1:0];

                            // Clamp a bordes (para que x0+1,y0+1 sigan dentro)
                            if (x0_tmp >= IMG_W-1) x0_tmp = IMG_W-2;
                            if (y0_tmp >= IMG_H-1) y0_tmp = IMG_H-2;

                            x0_lane[lane_idx] <= x0_tmp;
                            y0_lane[lane_idx] <= y0_tmp;
                            fx_lane[lane_idx] <= fx_tmp;
                            fy_lane[lane_idx] <= fy_tmp;
                        end

                        // Seleccionamos el vecino a leer
                        case (neigh_idx)
                            0: addr_tmp = y0_lane[lane_idx] * IMG_W + x0_lane[lane_idx];          // p00
                            1: addr_tmp = y0_lane[lane_idx] * IMG_W + (x0_lane[lane_idx] + 1);    // p10
                            2: addr_tmp = (y0_lane[lane_idx] + 1) * IMG_W + x0_lane[lane_idx];    // p01
                            default: addr_tmp = (y0_lane[lane_idx] + 1) * IMG_W
                                                  + (x0_lane[lane_idx] + 1);                      // p11
                        endcase

                        in_addr  <= addr_tmp;
                        rd_count <= rd_count + 1;
                    end

                    // -----------------------------------------
                    // LECTURA DE VECINOS (captura de datos)
                    // -----------------------------------------
                    S_READ_NEIGH_DATA: begin
                        case (neigh_idx)
                            0: p00_lane[lane_idx] <= in_rdata;
                            1: p10_lane[lane_idx] <= in_rdata;
                            2: p01_lane[lane_idx] <= in_rdata;
                            3: p11_lane[lane_idx] <= in_rdata;
                        endcase

                        // Avanzar vecino / lane
                        if (neigh_idx == 3) begin
                            neigh_idx <= 0;
                            if (lane_idx == LANES-1)
                                lane_idx <= 0; // fin del grupo
                            else
                                lane_idx <= lane_idx + 1;
                        end
                        else begin
                            neigh_idx <= neigh_idx + 1;
                        end
                    end

                    // -----------------------------------------
                    // CARGAR VECTORES PARA INTERP_SIMD4
                    // -----------------------------------------
                    S_INTERP_START: begin
                        for (i = 0; i < LANES; i = i + 1) begin
                            v_p00[i] <= p00_lane[i];
                            v_p10[i] <= p10_lane[i];
                            v_p01[i] <= p01_lane[i];
                            v_p11[i] <= p11_lane[i];
                            v_fx[i]  <= fx_lane[i];
                            v_fy[i]  <= fy_lane[i];
                        end
                    end

                    // -----------------------------------------
                    // ESCRITURA DE RESULTADOS
                    // -----------------------------------------
                    S_WRITE_GROUP: begin
                        x_lane_write = x_base + write_idx;

                        if (lane_active[write_idx]) begin
                            out_addr   <= y_out * OUT_W + x_lane_write;
                            out_wdata  <= v_pixel_out[write_idx];
                            out_we     <= 1'b1;
                            wr_count   <= wr_count + 1;
                        end

                        if (write_idx == LANES-1)
                            write_idx <= 0;
                        else
                            write_idx <= write_idx + 1;
                    end

                    // -----------------------------------------
                    // AVANZAR AL SIGUIENTE GRUPO
                    // -----------------------------------------
                    S_NEXT_GROUP: begin
                        if (x_base + LANES >= OUT_W) begin
                            // Siguiente fila
                            x_base <= 0;
                            y_out  <= y_out + 1;
                        end
                        else begin
                            // Siguiente grupo horizontal
                            x_base <= x_base + LANES;
                        end
                    end

                    default: begin
                        // nada
                    end

                endcase
            end
        end
    end

endmodule
