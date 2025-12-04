// ===============================================================
// controller_downscale_seq.sv
// Downscale con interpolación bilineal secuencial (1 píxel a la vez)
//
// Soporta 3 factores de escala seleccionables por hardware:
//
//   scale_mode = 2'b00  -> 1.0   (OUT = IMG_W x IMG_H)
//   scale_mode = 2'b01  -> 0.75  (OUT = 3/4 * IMG_W, 3/4 * IMG_H)
//   scale_mode = 2'b10  -> 0.5   (OUT = IMG_W/2, IMG_H/2)
//
// Para cada píxel de salida (x_out, y_out) se calcula una
// coordenada fuente (src_x_q, src_y_q) en Q0.FRAC y se hace
// interpolación bilineal usando interp_secuencial.
//
// Stepping controlado por allow_tick.
//
// ===============================================================

`timescale 1ns/1ps
import interp_pkg::*;

module controller_downscale_seq #(
    parameter int FRAC       = FRAC_BITS,
    parameter int IMG_W      = 512,
    parameter int IMG_H      = 512,
    parameter int ADDR_W     = 19
)(
    input  logic              clk,
    input  logic              rst_n,

    // Stepping
    input  logic              allow_tick,

    // Control de operación
    input  logic              start,
    output logic              done,

    // Selección de escala:
    //   2'b00 -> 1.0
    //   2'b01 -> 0.75
    //   2'b10 -> 0.5
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

    // Tamaños de salida para cada escala
    localparam int OUT_W_1_0  = IMG_W;
    localparam int OUT_H_1_0  = IMG_H;
    localparam int OUT_W_075  = (IMG_W * 3) / 4;
    localparam int OUT_H_075  = (IMG_H * 3) / 4;
    localparam int OUT_W_05   = IMG_W / 2;
    localparam int OUT_H_05   = IMG_H / 2;

    // Pasos en Q0.FRAC para cada escala (cuánto avanzamos en la imagen fuente
    // cuando movemos 1 píxel en la imagen destino).
    //
    //   escala 1.0  -> step = 1.0
    //   escala 0.75 -> step = 1 / 0.75 = 4/3
    //   escala 0.5  -> step = 2.0
    localparam int STEP_Q_1_0  = ONE_Q;           // 1.0
    localparam int STEP_Q_075  = (4 * ONE_Q) / 3; // ~1.3333
    localparam int STEP_Q_05   = 2 * ONE_Q;       // 2.0

    // ===========================================================
    // Selección de parámetros según scale_mode
    // (combinacional; se latchean al arrancar con start)
    // ===========================================================
    int unsigned out_w_sel, out_h_sel;
    int          step_x_q_sel, step_y_q_sel;

    always_comb begin
        case (scale_mode)
            2'b01: begin   // 0.75
                out_w_sel   = OUT_W_075;
                out_h_sel   = OUT_H_075;
                step_x_q_sel = STEP_Q_075;
                step_y_q_sel = STEP_Q_075;
            end
            2'b10: begin   // 0.5
                out_w_sel   = OUT_W_05;
                out_h_sel   = OUT_H_05;
                step_x_q_sel = STEP_Q_05;
                step_y_q_sel = STEP_Q_05;
            end
            default: begin // 1.0
                out_w_sel   = OUT_W_1_0;
                out_h_sel   = OUT_H_1_0;
                step_x_q_sel = STEP_Q_1_0;
                step_y_q_sel = STEP_Q_1_0;
            end
        endcase
    end

    // Valores latcheados al inicio de la operación (para que
    // no cambien si scale_mode cambia mientras estamos corriendo).
    int unsigned out_w_reg, out_h_reg;
    int          step_x_q,  step_y_q;

    // ===========================================================
    // Núcleo de interpolación bilineal secuencial
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
        S_SETUP,        // calcula x0,y0,fx,fy a partir de src_x_q,src_y_q
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

    // Coordenadas de salida
    int unsigned x_out, y_out;

    // Coordenadas de entrada (esquina del bloque 2x2) y fracciones
    int unsigned x0, y0;
    logic [FRAC-1:0] fx_reg, fy_reg;

    // Coordenadas fuente en Q0.FRAC
    q16_t src_x_q, src_y_q;

    // Vecinos
    u8_t p00_reg, p10_reg, p01_reg, p11_reg;

    // ===========================================================
    // Lógica combinacional FSM
    // ===========================================================
    always_comb begin
        // Defaults
        in_we      = 1'b0;
        in_wdata   = 8'd0;
        out_we     = 1'b0;
        out_wdata  = 8'd0;
        i_valid_in = 1'b0;
        next_state = state;
        done       = (state == S_DONE);

        case (state)
            S_IDLE: begin
                if (start)
                    next_state = S_SETUP;
            end

            S_SETUP: begin
                next_state = S_RD_P00_A;
            end

            S_RD_P00_A: next_state = S_RD_P00_D;
            S_RD_P00_D: next_state = S_RD_P10_A;
            S_RD_P10_A: next_state = S_RD_P10_D;
            S_RD_P10_D: next_state = S_RD_P01_A;
            S_RD_P01_A: next_state = S_RD_P01_D;
            S_RD_P01_D: next_state = S_RD_P11_A;
            S_RD_P11_A: next_state = S_RD_P11_D;
            S_RD_P11_D: next_state = S_INTERP_START;

            S_INTERP_START: begin
                i_valid_in = 1'b1;
                next_state = S_INTERP_WAIT;
            end

            S_INTERP_WAIT: begin
                if (i_valid_out)
                    next_state = S_WRITE;
            end

            S_WRITE: begin
                out_we    = 1'b1;
                out_wdata = i_pixel_out;
                next_state = S_NEXT;
            end

            S_NEXT: begin
                if ( (x_out == out_w_reg-1) && (y_out == out_h_reg-1) )
                    next_state = S_DONE;
                else
                    next_state = S_SETUP;
            end

            S_DONE: begin
                if (!start)
                    next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

    // ===========================================================
    // Secuencial: estado, coordenadas y contadores
    // ===========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;

            x_out       <= 0;
            y_out       <= 0;
            x0          <= 0;
            y0          <= 0;
            fx_reg      <= '0;
            fy_reg      <= '0;

            p00_reg     <= '0;
            p10_reg     <= '0;
            p01_reg     <= '0;
            p11_reg     <= '0;

            in_addr     <= '0;
            out_addr    <= '0;

            src_x_q     <= '0;
            src_y_q     <= '0;

            out_w_reg   <= OUT_W_05; // valores por defecto
            out_h_reg   <= OUT_H_05;
            step_x_q    <= STEP_Q_05;
            step_y_q    <= STEP_Q_05;

            cycle_count <= 32'd0;
            rd_count    <= 32'd0;
            wr_count    <= 32'd0;
        end
        else begin
            if (!allow_tick) begin
                // pausa por stepping
                state <= state;
            end
            else begin
                state <= next_state;

                // contador de ciclos (mientras no estemos en DONE)
                if (state != S_DONE)
                    cycle_count <= cycle_count + 1;

                case (state)
                    //-----------------------------------------
                    // Inicio: latch de parámetros de escala
                    //-----------------------------------------
                    S_IDLE: begin
							 if (start) begin
								  x_out       <= 0;
								  y_out       <= 0;

								  // Latch de parámetros según scale_mode
								  out_w_reg   <= out_w_sel;
								  out_h_reg   <= out_h_sel;
								  step_x_q    <= step_x_q_sel;
								  step_y_q    <= step_y_q_sel;

								  // 🔹 Inicialización distinta según escala
								  if (scale_mode == 2'b10) begin
										// 0.5 -> no usamos src_x_q/src_y_q en S_SETUP (tenemos caso especial)
										src_x_q <= '0;
										src_y_q <= '0;
								  end
								  else begin
										// 1.0 y 0.75 -> arrancar en el CENTRO del primer píxel
										// src_x_q = step_x_q / 2 ; src_y_q = step_y_q / 2
										src_x_q <= step_x_q_sel >>> 1;  // división entre 2
										src_y_q <= step_y_q_sel >>> 1;
								  end

								  cycle_count <= 32'd0;
								  rd_count    <= 32'd0;
								  wr_count    <= 32'd0;
							 end
						end


                    //-----------------------------------------
                    // Calcula x0,y0,fx,fy a partir de src_x_q,y_q
                    //-----------------------------------------
						// Dentro del always_ff @(posedge clk or negedge rst_n)
						// en el case (state)
							S_SETUP: begin
								 // ✅ CAMINO ESPECIAL PARA ESCALA 0.5 (scale_mode = 2'b10)
								 if (scale_mode == 2'b10) begin
									  // Mantenemos la lógica "simple" que ya funcionaba:
									  // bloque 2x2 con esquina (2*x_out, 2*y_out)
									  x0 <= x_out << 1;   // 2 * x_out
									  y0 <= y_out << 1;   // 2 * y_out

									  // Centro del bloque: fx = fy = 0.5 en QFRAC
									  fx_reg <= ONE_Q >> 1;
									  fy_reg <= ONE_Q >> 1;
								 end
								 else begin
									  // 🔹 Para 1.0 y 0.75 seguimos usando las coordenadas fuente genéricas
									  int unsigned x0_tmp, y0_tmp;

									  // Parte entera de src_x_q / src_y_q
									  x0_tmp = src_x_q >> FRAC;
									  y0_tmp = src_y_q >> FRAC;

									  // Clamp para evitar salirnos (x0+1, y0+1)
									  if (x0_tmp >= IMG_W-1)
											x0 <= IMG_W-2;
									  else
											x0 <= x0_tmp;

									  if (y0_tmp >= IMG_H-1)
											y0 <= IMG_H-2;
									  else
											y0 <= y0_tmp;

									  // Parte fraccionaria
									  fx_reg <= src_x_q[FRAC-1:0];
									  fy_reg <= src_y_q[FRAC-1:0];
								 end
							end


                    //-----------------------------------------
                    // Lecturas de vecinos (p00,p10,p01,p11)
                    //-----------------------------------------
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

                    //-----------------------------------------
                    // Lanza núcleo bilineal
                    //-----------------------------------------
                    S_INTERP_START: begin
                        i_p00 <= p00_reg;
                        i_p10 <= p10_reg;
                        i_p01 <= p01_reg;
                        i_p11 <= p11_reg;
                        i_fx  <= fx_reg;
                        i_fy  <= fy_reg;
                    end

                    //-----------------------------------------
                    // Escritura de resultado
                    //-----------------------------------------
                    S_WRITE: begin
                        out_addr <= y_out * out_w_reg + x_out;
                        wr_count <= wr_count + 1;
                    end

                    //-----------------------------------------
                    // Avanzar a siguiente píxel de salida
                    //-----------------------------------------
							S_NEXT: begin
								 if (x_out == out_w_reg-1) begin
									  // Fin de fila
									  x_out <= 0;

									  if (scale_mode == 2'b10) begin
											// Escala 0.5: usamos el camino especial (2×2 con centro),
											// src_x_q no se usa en S_SETUP, así que puede quedar en 0.
											src_x_q <= '0;
									  end
									  else begin
											// Escalas 0.75 (01) y 1.0 (00):
											// reiniciamos src_x_q al CENTRO del primer píxel de la fila
											// src_x_q = step_x_q / 2
											src_x_q <= step_x_q >>> 1;  // si se queja, usar: src_x_q <= step_x_q / 2;
									  end

									  if (y_out != out_h_reg-1) begin
											y_out   <= y_out + 1;
											src_y_q <= src_y_q + step_y_q;
									  end
								 end
								 else begin
									  // Siguiente columna
									  x_out   <= x_out + 1;
									  src_x_q <= src_x_q + step_x_q;
								 end
							end


                    default: ;
                endcase
            end
        end
    end

endmodule
