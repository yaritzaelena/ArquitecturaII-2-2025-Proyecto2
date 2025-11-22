// ram_img.sv
// RAM simple de una puerta (1R/1W) para imagen

`timescale 1ns/1ps

module ram_img #(
  parameter int ADDR_WIDTH = 19,   // soporta 2^ADDR_WIDTH posiciones
  parameter int DATA_WIDTH = 8
)(
  input  logic                     clk,
  input  logic                     we,        // write enable
  input  logic [ADDR_WIDTH-1:0]    addr,
  input  logic [DATA_WIDTH-1:0]    wdata,
  output logic [DATA_WIDTH-1:0]    rdata
);

  localparam int DEPTH = 1 << ADDR_WIDTH;

  // memoria real
  logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

  always_ff @(posedge clk) begin
    if (we) begin
      mem[addr] <= wdata;   // escritura sincronizada
    end
    rdata <= mem[addr];     // lectura sincronizada
  end

endmodule
