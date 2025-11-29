`timescale 1ns/1ps

// step_controller.sv
// Módulo simple para implementar stepping funcional.
// A partir de comandos de la PC (o testbench) genera la señal allow_tick:
//
//  - cmd_halt     = 1  -> se detiene la ejecución (no avanza la FSM)
//  - cmd_continue = 1  -> ejecución continua (allow_tick = 1 siempre)
//  - cmd_step     = 1  -> se habilita exactamente un ciclo de avance
//
// La idea es que estos comandos se decodifican desde JTAG/UART en otro módulo
// y aquí solo se centraliza la lógica de control de stepping.

module step_controller (
    input  logic clk,
    input  logic rst_n,

    input  logic cmd_step,
    input  logic cmd_continue,
    input  logic cmd_halt,

    output logic allow_tick,   // 1 = controlador puede avanzar
    output logic halted        // 1 = en modo detenido/stepping
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            halted     <= 1'b1;   // al inicio se deja detenido
            allow_tick <= 1'b0;
        end
        else begin
            // Comandos tienen prioridad (se asume pulsos 1 ciclo)
            if (cmd_halt) begin
                halted     <= 1'b1;
                allow_tick <= 1'b0;
            end
            else if (cmd_continue) begin
                halted     <= 1'b0;
                allow_tick <= 1'b1;   // ejecución libre
            end
            else if (cmd_step) begin
                // Un solo ciclo de avance: allow_tick = 1 por este ciclo
                halted     <= 1'b1;
                allow_tick <= 1'b1;
            end
            else begin
                // Si estamos detenidos, no se permite avanzar
                if (halted) begin
                    allow_tick <= 1'b0;
                end
                else begin
                    allow_tick <= 1'b1; // modo continuo
                end
            end
        end
    end

endmodule
