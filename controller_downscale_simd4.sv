// ===============================================================
// controller_downscale_simd4.sv
// Controlador SIMD (4 lanes) para downscaling con interpolación bilineal
//
// Versión vectorial del controller_downscale_seq:
//   - Procesa 4 píxeles de salida "en grupo" usando interp_simd4.
//   - Entrada: imagen IMG_W x IMG_H en RAM de entrada (ram_img).
//   - Salida: imagen reducida OUT_W x OUT_H en RAM de salida (ram_img).
//   - Factor de escala = SCALE_NUM / SCALE_DEN (0.5–1.0).
//   - Stepping controlado por allow_tick.
//   - Contadores de ciclos, lecturas y escrituras.
//
// RAM es single-port, por eso las lecturas de vecinos se serializan:
//   - Para cada grupo de 4 píxeles, se hacen 16 lecturas (4 vecinos x lane).
// ===============================================================

`timescale 1ns/1ps
import interp_pkg::*;

module controller_downscale_simd4 #(
    parameter int FRAC       = FRAC_BITS,
    parameter int IMG_W      = 512,
    parameter int IMG_H      = 512,
    parameter int ADDR_W     = 19,
    parameter int LANES      = 4,

    // Factor de escala = SCALE_NUM / SCALE_DEN (0.5–1.0)
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
    localparam int OUT_W   = (IMG_W * SCALE_NUM) / SCALE_DEN;
    localparam int OUT_H   = (IMG_H * SCALE_NUM) / SCALE_DEN;
    localparam int ONE_Q   = 1 << FRAC;

    // ===========================================================
    // Señales hacia interp_simd4
    // ===========================================================
    logic        v_valid_in;
    logic        v_valid_out;

    // Vecinos por lane
    u8_t         v_p00   [LANES];
    u8_t         v_p10   [LANES];
    u8_t         v_p01   [LANES];
    u8_t         v_p11   [LANES];

    logic [FRAC-1:0] v_fx[LANES];
    logic [FRAC-1:0] v_fy[LANES];

    u8_t         v_pixel_out[LANES];

    // Instancia del núcleo SIMD: interp_simd4
   
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


    // ===========================================================
    // FSM principal
    // ===========================================================
    typedef enum logic [3:0] {
        S_IDLE,
        S_SETUP_GROUP,       // prepara 4 píxeles destino
        S_READ_NEIGH_ADDR,   // seleccionar vecino y lane para lectura
        S_READ_NEIGH_DATA,   // capturar dato desde RAM
        S_INTERP_START,      // lanzar SIMD
        S_INTERP_WAIT,       // esperar valid_out
        S_WRITE_GROUP,       // escribir hasta 4 píxeles
        S_NEXT_GROUP,        // avanzar x,y
        S_DONE
    } state_t;

    state_t state, next_state;

    // Coordenadas destino base de grupo
    int unsigned x_base;        // x del lane 0
    int unsigned y_out;

    // Para cada lane, coordenadas fuente y datos de vecinos
    q16_t             src_x_q [LANES];
    q16_t             src_y_q [LANES];
    int unsigned      x0_lane [LANES];
    int unsigned      y0_lane [LANES];
    logic [FRAC-1:0]  fx_lane [LANES];
    logic [FRAC-1:0]  fy_lane [LANES];

    // Vecinos leídos de RAM
    u8_t p00_lane [LANES];
    u8_t p10_lane [LANES];
    u8_t p01_lane [LANES];
    u8_t p11_lane [LANES];

    // Índices para lectura de vecinos y escritura de salida
    int unsigned lane_idx;      // 0..LANES-1
    int unsigned neigh_idx;     // 0..3 (p00,p10,p01,p11)
    int unsigned write_idx;     // 0..LANES-1 (para escribir píxeles)

    // Lanes activos (para manejar OUT_W no múltiplo de LANES)
    logic lane_active[LANES];

    // Variables temporales para cálculos (declaradas fuera del always)
    int unsigned i;
    int unsigned x_lane_tmp;
    int unsigned x0_tmp, y0_tmp;
    int unsigned xl, yl;
    logic [FRAC-1:0] fx_tmp, fy_tmp;
    logic [ADDR_W-1:0] addr_tmp;
    int unsigned x_lane_write;
    int unsigned y_src_idx;

    // ===========================================================
    // Defaults combinacionales
    // ===========================================================
    always_comb begin
        in_we      = 1'b0;
        in_wdata   = 8'd0;
        out_we     = 1'b0;
        out_wdata  = 8'd0;
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
                // Se selecciona in_addr en la parte secuencial
                next_state = S_READ_NEIGH_DATA;
            end

            S_READ_NEIGH_DATA: begin
                // Capturamos in_rdata y avanzamos lane/neigh
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
                // escritura serial de cada lane activo
                out_we    = lane_active[write_idx];
                out_wdata = v_pixel_out[write_idx];

                if (write_idx == LANES-1)
                    next_state = S_NEXT_GROUP;
            end

            S_NEXT_GROUP: begin
                // Si acabamos de procesar el ÚLTIMO grupo de la ÚLTIMA fila,
                // pasamos a S_DONE. En cualquier otro caso, volvemos a S_SETUP_GROUP
                // para procesar el siguiente grupo.
                if ((x_base + LANES >= OUT_W) && (y_out == OUT_H-1))
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

            // Inicialización de arrays
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
                // pausa por stepping
                state <= state;
            end
            else begin
                state <= next_state;

                // Contador de ciclos
                if (state != S_DONE)
                    cycle_count <= cycle_count + 1;

                case (state)
                    S_IDLE: begin
                        if (start) begin
                            x_base   <= 0;
                            y_out    <= 0;
                            lane_idx <= 0;
                            neigh_idx<= 0;
                            write_idx<= 0;

                            // Coordenada Y fuente común para todos los lanes de la fila 0
                            for (i = 0; i < LANES; i = i + 1) begin
                                src_y_q[i] <= 0;
                            end
                        end
                    end

                    S_SETUP_GROUP: begin
                        // Determinar qué lanes están activos en este grupo
                        for (i = 0; i < LANES; i = i + 1) begin
                            x_lane_tmp      = x_base + i;
                            lane_active[i]  <= (x_lane_tmp < OUT_W);
                            // Calcular coordenada fuente X para este lane
                            src_x_q[i]      <= (x_lane_tmp * SCALE_DEN * ONE_Q) / SCALE_NUM;
                            // Y ya está en src_y_q[i] (se actualiza por fila en S_NEXT_GROUP)
                        end

                        // Reiniciar índices de lectura
                        lane_idx  <= 0;
                        neigh_idx <= 0;
                    end

                    // ---------------------------------------------------
                    // Lectura de vecinos serializada: 16 lecturas por grupo
                    // ---------------------------------------------------
                    S_READ_NEIGH_ADDR: begin
                        // Para el primer vecino de cada lane calculamos x0,y0,fx,fy
                        if (neigh_idx == 0) begin
                            x0_tmp = src_x_q[lane_idx] >> FRAC;
                            y0_tmp = src_y_q[lane_idx] >> FRAC;
                            fx_tmp = src_x_q[lane_idx][FRAC-1:0];
                            fy_tmp = src_y_q[lane_idx][FRAC-1:0];

                            // Clamp a bordes
                            if (x0_tmp >= IMG_W-1) x0_tmp = IMG_W-2;
                            if (y0_tmp >= IMG_H-1) y0_tmp = IMG_H-2;

                            x0_lane[lane_idx] <= x0_tmp;
                            y0_lane[lane_idx] <= y0_tmp;
                            fx_lane[lane_idx] <= fx_tmp;
                            fy_lane[lane_idx] <= fy_tmp;

                            xl <= x0_tmp;
                            yl <= y0_tmp;
                        end
                        else begin
                            xl <= x0_lane[lane_idx];
                            yl <= y0_lane[lane_idx];
                        end

                        // Selección del vecino
                        case (neigh_idx)
                            0: addr_tmp = yl * IMG_W + xl;          // p00
                            1: addr_tmp = yl * IMG_W + (xl + 1);    // p10
                            2: addr_tmp = (yl + 1) * IMG_W + xl;    // p01
                            default: addr_tmp = (yl + 1) * IMG_W + (xl + 1); // p11
                        endcase

                        in_addr  <= addr_tmp;
                        rd_count <= rd_count + 1;
                    end

                    S_READ_NEIGH_DATA: begin
                        // Guardar el dato leído en el buffer adecuado
                        case (neigh_idx)
                            0: p00_lane[lane_idx] <= in_rdata;
                            1: p10_lane[lane_idx] <= in_rdata;
                            2: p01_lane[lane_idx] <= in_rdata;
                            3: p11_lane[lane_idx] <= in_rdata;
                        endcase

                        // Avanzar al siguiente vecino / lane
                        if (neigh_idx == 3) begin
                            neigh_idx <= 0;
                            if (lane_idx == LANES-1)
                                lane_idx <= 0; // terminado grupo
                            else
                                lane_idx <= lane_idx + 1;
                        end
                        else begin
                            neigh_idx <= neigh_idx + 1;
                        end
                    end

                    // ---------------------------------------------------
                    // Lanzar interpolación SIMD
                    // ---------------------------------------------------
                    S_INTERP_START: begin
                        // Cargar todos los vecinos y fracciones en los vectores para interp_simd4
                        for (i = 0; i < LANES; i = i + 1) begin
                            v_p00[i] <= p00_lane[i];
                            v_p10[i] <= p10_lane[i];
                            v_p01[i] <= p01_lane[i];
                            v_p11[i] <= p11_lane[i];
                            v_fx[i]  <= fx_lane[i];
                            v_fy[i]  <= fy_lane[i];
                        end
                    end

                    // ---------------------------------------------------
                    // Escritura de los 4 píxeles de salida
                    // ---------------------------------------------------
                    S_WRITE_GROUP: begin
                        x_lane_write = x_base + write_idx;
                        if (lane_active[write_idx]) begin
                            out_addr <= y_out * OUT_W + x_lane_write;
                            wr_count <= wr_count + 1;
                        end

                        if (write_idx == LANES-1)
                            write_idx <= 0;
                        else
                            write_idx <= write_idx + 1;
                    end

                    // ---------------------------------------------------
                    // Avanzar al siguiente grupo de píxeles
                    // ---------------------------------------------------
						 S_NEXT_GROUP: begin
							  if (x_base + LANES >= OUT_W) begin
									// Ya no hay más grupos en esta fila
									if (y_out != OUT_H-1) begin
										 // Pasar a la siguiente fila
										 x_base <= 0;
										 y_out  <= y_out + 1;

										 // Nueva coordenada Y fuente para todos los lanes
										 y_src_idx = y_out + 1;
										 for (i = 0; i < LANES; i = i + 1) begin
											  src_y_q[i] <= (y_src_idx * SCALE_DEN * ONE_Q) / SCALE_NUM;
										 end
									end
									else begin
										 // Última fila -> NO tocar x_base ni y_out aquí.
										 // La lógica combinacional detecta esta condición
										 // y en el próximo ciclo irá a S_DONE.
									end
							  end
							  else begin
									// Siguiente grupo horizontal en la misma fila
									x_base <= x_base + LANES;
							  end
						 end


                    default: begin
                        // nada adicional
                    end
                endcase
            end
        end
    end

endmodule
