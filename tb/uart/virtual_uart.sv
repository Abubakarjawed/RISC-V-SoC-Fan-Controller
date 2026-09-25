`timescale 1ns/1ps

import uart_pkg::*;

module virtual_uart (
    input  logic rx_pin,  // Connected to SoC uart_tx
    output logic tx_pin   // Connected to SoC uart_rx
);

    event                    byte_received;
    logic [DATA_WIDTH_8-1:0] last_rx_byte = 'h00;
    string                   line_buffer  = "";

    // Engine B: Virtual Keyboard (Tx Line Initialization)
    initial begin
        tx_pin = 1'b1; 
    end

    // Engine A: Virtual Display (Rx Line Listener)
    initial begin
        logic [DATA_WIDTH_8-1:0] rx_shift_reg;

        forever begin
            @(negedge rx_pin); // -> Start Bit
            #(BIT_PERIOD / 2.0);

            if (rx_pin === 1'b0) begin
                for (int i = 0; i < 8; i++) begin
                    #(BIT_PERIOD);
                    rx_shift_reg[i] = rx_pin;
                end
            end

            #(BIT_PERIOD);

            if (rx_pin === 1'b1) begin // Validation
                last_rx_byte = rx_shift_reg;

                $write("%c", rx_shift_reg);
                $fflush(); // Flush stdout buffer immediately

                if (rx_shift_reg == 8'h0A || rx_shift_reg == 8'h0D) begin
                    if (line_buffer.len() > 0) begin
                        $display("\n[UART TERMINAL] %s", line_buffer);
                        line_buffer = "";
                    end
                end else if (rx_shift_reg != 8'h00) begin
                    line_buffer = {line_buffer, string'(rx_shift_reg)};
                end

                -> byte_received; // event trigger
            end else begin
                $warning("[UART TERMINAL ERROR] Framing Error Detected! Missing Stop Bit.");
            end
        end
    end
    
    // Engine B: Transmitter Tasks (Interactive Keyboard) -> (Start + 8 Data + Stop)
    task automatic send_byte(input logic [7:0] data);
        begin
            // Start Bit (Low)
            tx_pin = 1'b0;
            #(BIT_PERIOD);

            // 8 Data Bits
            for (int i = 0; i < 8; i++) begin
                tx_pin = data[i];
                #(BIT_PERIOD);
            end

            // Stop Bit (High)
            tx_pin = 1'b1;
            #(BIT_PERIOD);
        end
    endtask 

    task automatic send_string(input string msg);
        begin
            for (int i = 0; i < msg.len(); i++) begin
                send_byte(msg[i]);
            end
        end
    endtask

endmodule
