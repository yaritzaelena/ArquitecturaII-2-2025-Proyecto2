// ===============================================================
// controller_downscale_seq.sv  (VERSION FINAL)
//
// Downscale secuencial con interpolación bilineal.
// Corrige:
//   - Error de “cuadruplificación” en 0.75 y 1.0
//   - Drivers múltiples en out_we / out_wdata
//   - Problemas de compilación en ModelSim (vlog-2244)
//   - Coordenadas fuente en Q0.FRAC robustas
// ===============================================================

`timescale 1ns/1ps
import interp_pkg::*;

module controller_downscale_seq #(
    parameter int FRAC   = FRAC_BITS,
    parameter int IMG_W  = 512,
    parameter int IMG_H  = 512,
    parameter int ADDR_W = 19
)(
    input  logic              clk,
    input  logic              rst_n,

    // Stepping
    input  logic              allow_tick,

    // Control
    input  logic              start,
    output logic              done,

    // 00 = 1.0
    // 01 = 0.75
    // 10 = 0.5
    input  logic [1:0]        scale_mode,

    // RAM entrada
    output logic              in_we,
    output logic [ADDR_W-1:0] in_addr,
    output logic [7:0]        in_wdata,
    input  logic [7:0]        in_rdata,

    // RAM salida
    output logic              out_we,
    output logic [ADDR_W-1:0] out_addr,
    output logic [7:0]        out_wdata,

    // contadores
    output logic [31:0]       cycle_count,
    output logic [31:0]       rd_count,
    output logic [31:0]       wr_count
);

    // ===========================================================
    // Parámetros derivados
    // ===========================================================
    localparam int ONE_Q = 1 << FRAC;

    localparam int OUT_W_1_0 = IMG_W;
    localparam int OUT_H_1_0 = IMG_H;
    localparam int OUT_W_075 = (IMG_W * 3) / 4;
    localparam int OUT_H_075 = (IMG_H * 3) / 4;
    localparam int OUT_W_05  = IMG_W / 2;
    localparam int OUT_H_05  = IMG_H / 2;

    localparam int STEP_Q_1_0 = ONE_Q;           // 1.0
    localparam int STEP_Q_075 = (4 * ONE_Q) / 3; // ~1.333
    localparam int STEP_Q_05  = 2 * ONE_Q;       // 2.0

    // ===========================================================
    // Selección combinacional según scale_mode
    // ===========================================================
    int unsigned out_w_sel, out_h_sel;
    int          step_x_q_sel, step_y_q_sel;

    always_comb begin
        case (scale_mode)
            2'b01: begin // 0.75
                out_w_sel    = OUT_W_075;
                out_h_sel    = OUT_H_075;
                step_x_q_sel = STEP_Q_075;
                step_y_q_sel = STEP_Q_075;
            end
            2'b10: begin // 0.5
                out_w_sel    = OUT_W_05;
                out_h_sel    = OUT_H_05;
                step_x_q_sel = STEP_Q_05;
                step_y_q_sel = STEP_Q_05;
            end
            default: begin // 1.0
                out_w_sel    = OUT_W_1_0;
                out_h_sel    = OUT_H_1_0;
                step_x_q_sel = STEP_Q_1_0;
                step_y_q_sel = STEP_Q_1_0;
            end
        endcase
    end

    int unsigned out_w_reg, out_h_reg;
    int          step_x_q, step_y_q;

    // ===========================================================
    // Acumuladores de coordenada fuente Q0.FRAC (32 bits)
    // ===========================================================
    logic [31:0] src_x_q, src_y_q;

    // Coordenadas salida
    int unsigned x_out, y_out;

    // Coordenadas entrada
    int unsigned x0, y0;

    // Fracciones
    logic [FRAC-1:0] fx_reg, fy_reg;

    // Vecinos 2x2
    u8_t p00_reg, p10_reg, p01_reg, p11_reg;

    // ===========================================================
    // Interpolador bilineal secuencial
    // ===========================================================
    logic        i_valid_in, i_valid_out;
    u8_t         i_p00, i_p10, i_p01, i_p11;
    logic [FRAC-1:0] i_fx, i_fy;
    u8_t         i_pixel_out;

    interp_secuencial #(.FRAC(FRAC)) u_interp (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (i_valid_in),
        .p00       (i_p00),
        .p10       (i_p10),
        .p01       (i_p01),
        .p11       (i_p11),
        .fx        (i_fx),
        .fy        (i_fy),
        .valid_out (i_valid_out),
        .pixel_out (i_pixel_out)
    );

    // ===========================================================
    // FSM
    // ===========================================================

    typedef enum logic [3:0] {
        S_IDLE,
        S_SETUP,
        S_RD_P00_A, S_RD_P00_D,
        S_RD_P10_A, S_RD_P10_D,
        S_RD_P01_A, S_RD_P01_D,
        S_RD_P11_A, S_RD_P11_D,
        S_INTERP_START,
        S_INTERP_WAIT,
        S_WRITE,
        S_NEXT,
        S_DONE
    } state_t;

    state_t state, next_state;

    // ===========================================================
    // FSM combinacional (sin out_we/out_wdata)
    // ===========================================================
    always_comb begin
        in_we      = 1'b0;
        in_wdata   = 8'd0;
        i_valid_in = 1'b0;

        done       = (state == S_DONE);
        next_state = state;

        case (state)

            S_IDLE: if (start) next_state = S_SETUP;

            S_SETUP:        next_state = S_RD_P00_A;
            S_RD_P00_A:     next_state = S_RD_P00_D;
            S_RD_P00_D:     next_state = S_RD_P10_A;
            S_RD_P10_A:     next_state = S_RD_P10_D;
            S_RD_P10_D:     next_state = S_RD_P01_A;
            S_RD_P01_A:     next_state = S_RD_P01_D;
            S_RD_P01_D:     next_state = S_RD_P11_A;
            S_RD_P11_A:     next_state = S_RD_P11_D;
            S_RD_P11_D:     next_state = S_INTERP_START;

            S_INTERP_START: begin
                i_valid_in = 1'b1;
                next_state = S_INTERP_WAIT;
            end

            S_INTERP_WAIT:
                if (i_valid_out) next_state = S_WRITE;

            S_WRITE:
                next_state = S_NEXT;

            S_NEXT: begin
                if ((x_out == out_w_reg-1) && (y_out == out_h_reg-1))
                    next_state = S_DONE;
                else
                    next_state = S_SETUP;
            end

            S_DONE:
                if (!start) next_state = S_IDLE;

        endcase
    end

    // ===========================================================
    // Secuencial (único lugar donde se manejan out_we/out_wdata)
    // ===========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;

            x_out <= 0;   y_out <= 0;
            x0    <= 0;   y0    <= 0;

            fx_reg <= '0;
            fy_reg <= '0;

            p00_reg <= '0;
            p10_reg <= '0;
            p01_reg <= '0;
            p11_reg <= '0;

            in_addr  <= 0;
            out_addr <= 0;

            src_x_q <= 0;
            src_y_q <= 0;

            step_x_q <= STEP_Q_05;
            step_y_q <= STEP_Q_05;

            out_w_reg <= OUT_W_05;
            out_h_reg <= OUT_H_05;

            cycle_count <= 0;
            rd_count    <= 0;
            wr_count    <= 0;

            out_we    <= 0;
            out_wdata <= 0;
        end
        else begin
            if (!allow_tick) begin
                state <= state; // pausa
            end
            else begin
                state <= next_state;

                // defaults por ciclo
                out_we    <= 1'b0;
                out_wdata <= 8'd0;

                if (state != S_DONE)
                    cycle_count <= cycle_count + 1;

                case (state)

                    // -----------------------------------------
                    // INICIO
                    // -----------------------------------------
                    S_IDLE: if (start) begin
                        x_out <= 0;
                        y_out <= 0;

                        out_w_reg <= out_w_sel;
                        out_h_reg <= out_h_sel;

                        step_x_q <= step_x_q_sel;
                        step_y_q <= step_y_q_sel;

                        cycle_count <= 0;
                        rd_count    <= 0;
                        wr_count    <= 0;

                        if (scale_mode == 2'b10) begin
                            src_x_q <= 0;
                            src_y_q <= 0;
                        end else begin
                            src_x_q <= step_x_q_sel >> 1;
                            src_y_q <= step_y_q_sel >> 1;
                        end
                    end

                    // -----------------------------------------
                    // SETUP
                    // -----------------------------------------
                    S_SETUP: begin
                        if (scale_mode == 2'b10) begin
                            // escala 0.5 (caso especial)
                            x0     <= x_out << 1;
                            y0     <= y_out << 1;
                            fx_reg <= ONE_Q >> 1;
                            fy_reg <= ONE_Q >> 1;
                        end
                        else begin
                            int unsigned x0_tmp, y0_tmp;
                            int unsigned max_x0;
                            int unsigned max_y0;

                            max_x0 = IMG_W - 2;
                            max_y0 = IMG_H - 2;

                            x0_tmp = src_x_q >> FRAC;
                            y0_tmp = src_y_q >> FRAC;

                            x0 <= (x0_tmp > max_x0) ? max_x0 : x0_tmp;
                            y0 <= (y0_tmp > max_y0) ? max_y0 : y0_tmp;

                            fx_reg <= src_x_q[FRAC-1:0];
                            fy_reg <= src_y_q[FRAC-1:0];
                        end
                    end

                    // -----------------------------------------
                    // LECTURAS
                    // -----------------------------------------
                    S_RD_P00_A: begin
                        in_addr  <= y0 * IMG_W + x0;
                        rd_count <= rd_count + 1;
                    end
                    S_RD_P00_D: p00_reg <= in_rdata;

                    S_RD_P10_A: begin
                        in_addr  <= y0 * IMG_W + (x0 + 1);
                        rd_count <= rd_count + 1;
                    end
                    S_RD_P10_D: p10_reg <= in_rdata;

                    S_RD_P01_A: begin
                        in_addr  <= (y0 + 1) * IMG_W + x0;
                        rd_count <= rd_count + 1;
                    end
                    S_RD_P01_D: p01_reg <= in_rdata;

                    S_RD_P11_A: begin
                        in_addr  <= (y0 + 1) * IMG_W + (x0 + 1);
                        rd_count <= rd_count + 1;
                    end
                    S_RD_P11_D: p11_reg <= in_rdata;

                    // -----------------------------------------
                    // INTERP
                    // -----------------------------------------
                    S_INTERP_START: begin
                        i_p00 <= p00_reg;
                        i_p10 <= p10_reg;
                        i_p01 <= p01_reg;
                        i_p11 <= p11_reg;
                        i_fx  <= fx_reg;
                        i_fy  <= fy_reg;
                    end

                    // -----------------------------------------
                    // ESCRITURA
                    // -----------------------------------------
                    S_WRITE: begin
                        out_addr   <= y_out * out_w_reg + x_out;
                        out_wdata  <= i_pixel_out;
                        out_we     <= 1'b1;
                        wr_count   <= wr_count + 1;
                    end

                    // -----------------------------------------
                    // SIGUIENTE PIXEL
                    // -----------------------------------------
                    S_NEXT: begin
                        if (x_out == out_w_reg-1) begin
                            x_out <= 0;

                            if (scale_mode == 2'b10)
                                src_x_q <= 0;
                            else
                                src_x_q <= step_x_q >> 1;

                            if (y_out != out_h_reg-1) begin
                                y_out   <= y_out + 1;
                                src_y_q <= src_y_q + step_y_q;
                            end
                        end
                        else begin
                            x_out   <= x_out + 1;
                            src_x_q <= src_x_q + step_x_q;
                        end
                    end

                endcase
            end
        end
    end

endmodule
