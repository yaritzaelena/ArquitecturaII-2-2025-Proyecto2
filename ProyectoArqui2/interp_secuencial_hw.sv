module interp_secuencial_hw #(
  parameter ADDR_W = 16
)(
  input  logic              clk,
  input  logic              rst,
  input  logic              start,

  // Parámetros de imagen
  input  logic [15:0]       width,
  input  logic [15:0]       height,

  // Direcciones base en memoria
  input  logic [ADDR_W-1:0] base_in,
  input  logic [ADDR_W-1:0] base_out,

  
  // input interp_pkg::q8_8_t scale_q,

  // Interfaz sencilla a RAM (ejemplo, adáptalo a lo que les pidieron)
  output logic [ADDR_W-1:0] mem_addr,
  output logic              mem_rd,
  input  logic [7:0]        mem_rdata,
  input  logic              mem_rvalid,
  output logic              mem_wr,
  output logic [7:0]        mem_wdata,

  output logic              busy,
  output logic              done
);
  import interp_pkg::*;

  // -------------------------------------------------------------------
  // 1) Registros para coordenadas y estados
  // -------------------------------------------------------------------
	typedef enum logic [3:0] {
		 S_IDLE,
		 S_INIT,
		 S_READ_P00,
		 S_READ_P10,
		 S_READ_P01,
		 S_READ_P11,
		 S_COMPUTE,
		 S_WRITE,
		 S_NEXT
	} state_t;


  state_t state, next_state;

  logic [15:0] x, y;       // coordenadas del píxel de salida
  logic [7:0]  p00, p10, p01, p11;
  q8_8_t       fx_q, fy_q; // por ahora podés iniciar en 0 si solo probás el flujo

  logic [7:0]  out_pixel;

  // Instancia del núcleo combinacional
  interpolador_hw u_interp (
    .p00  (p00),
    .p10  (p10),
    .p01  (p01),
    .p11  (p11),
    .fx_q (fx_q),
    .fy_q (fy_q),
    .out  (out_pixel)
  );

  // -------------------------------------------------------------------
  // 2) FSM secuencial: estados
  // -------------------------------------------------------------------
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= S_IDLE;
      x     <= '0;
      y     <= '0;
    end else begin
      state <= next_state;
      // Actualización de contadores en el estado correspondiente
      if (state == S_NEXT) begin
        if (x == width-1) begin
          x <= 0;
          if (y == height-1)
            y <= 0;
          else
            y <= y + 1;
        end else begin
          x <= x + 1;
        end
      end
    end
  end

  // -------------------------------------------------------------------
  // 3) Lógica combinacional: siguiente estado y control de RAM
  // -------------------------------------------------------------------
  always_comb begin
    // Valores por defecto
    mem_rd     = 1'b0;
    mem_wr     = 1'b0;
    mem_addr   = '0;
    mem_wdata  = '0;
    busy       = 1'b1;
    done       = 1'b0;
    next_state = state;

    case (state)
      S_IDLE: begin
        busy = 1'b0;
        if (start) begin
          // Empezar en (0,0); fx_q, fy_q pueden ser 0 al inicio
          next_state = S_INIT;
        end
      end

      S_INIT: begin
        // Podrías inicializar fx_q, fy_q aquí.
        // Por ejemplo, para probar flujo, usar 0.0:
        // fx_q = 16'sh0000;
        // fy_q = 16'sh0000;
        next_state = S_READ_P00;
      end

      // Leer P00
      S_READ_P00: begin
        mem_rd   = 1'b1;
        mem_addr = base_in + (y * width + x);
        if (mem_rvalid) begin
          // Se captura p00 en un always_ff con enable (ver más abajo)
          next_state = S_READ_P10;
        end
      end

      // Leer P10 (x+1, y)
      S_READ_P10: begin
        mem_rd   = 1'b1;
        mem_addr = base_in + (y * width + (x+1 < width ? x+1 : x));
        if (mem_rvalid)
          next_state = S_READ_P01;
      end

      // Leer P01 (x, y+1)
      S_READ_P01: begin
        mem_rd   = 1'b1;
        mem_addr = base_in + ((y+1 < height ? y+1 : y) * width + x);
        if (mem_rvalid)
          next_state = S_READ_P11;
      end

      // Leer P11 (x+1, y+1)
      S_READ_P11: begin
        mem_rd   = 1'b1;
        mem_addr = base_in +
                   ((y+1 < height ? y+1 : y) * width +
                    (x+1 < width  ? x+1 : x));
        if (mem_rvalid)
          next_state = S_COMPUTE;
      end

      // Cálculo combinacional (un ciclo)
      S_COMPUTE: begin
        // El u_interp ya está calculando out_pixel combinacionalmente
        next_state = S_WRITE;
      end

      // Escritura del píxel de salida
      S_WRITE: begin
        mem_wr    = 1'b1;
        mem_wdata = out_pixel;
        mem_addr  = base_out + (y * width + x);
        // asumiendo una sola escritura por ciclo, pasamos al siguiente
        next_state = S_NEXT;
      end

      // Avanzar al siguiente píxel o terminar
      S_NEXT: begin
        if ((x == width-1) && (y == height-1)) begin
          done       = 1'b1;
          next_state = S_IDLE;
        end else begin
          next_state = S_READ_P00;
        end
      end

      default: next_state = S_IDLE;
    endcase
  end

  // -------------------------------------------------------------------
  // 4) Captura de p00, p10, p01, p11 cuando llega mem_rdata
  // -------------------------------------------------------------------
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      p00 <= '0;
      p10 <= '0;
      p01 <= '0;
      p11 <= '0;
      fx_q <= '0;
      fy_q <= '0;
    end else begin
      if (state == S_READ_P00 && mem_rvalid) p00 <= mem_rdata;
      if (state == S_READ_P10 && mem_rvalid) p10 <= mem_rdata;
      if (state == S_READ_P01 && mem_rvalid) p01 <= mem_rdata;
      if (state == S_READ_P11 && mem_rvalid) p11 <= mem_rdata;

    end
  end

endmodule
