import uart_pkg::*;

module receiver (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    baud_tick,
    input  logic                    rx_pin,
    input  parity_e                 parity_mode,
    input  stop_e                   stop_mode,
    output logic                    rx_done,
    output logic [DATA_WIDTH_8-1:0] rx_data,
    output logic                    parity_err
);
        
    logic rx_sync_0;
    logic rx_sync_1;
    logic [3:0] tick_count; // 4 bit counter
    logic [3:0] bit_count;
    logic [DATA_WIDTH_8-1:0] rx_data_reg;
    logic parity_bit_reg;

    // 2 stage DFF Sync
    always_ff @(posedge clk or negedge rst_n) begin // UART uses active-low signals
        if (!rst_n) begin
            rx_sync_0 <= 1'b1;
            rx_sync_1 <= 1'b1;
        end else begin
            rx_sync_0 <= rx_pin;
            rx_sync_1 <= rx_sync_0;
        end
    end

    state_t state;

    // FSM: using 2 block approach
    always_ff @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin
            state          <= IDLE;
            rx_done        <= 1'b0;
            rx_data        <= '0;
            tick_count     <= 4'd0;
            bit_count      <= 4'd0;
            rx_data_reg    <= '0;
            parity_bit_reg <= 1'b0;
            parity_err     <= 1'b0;        
        end else begin
            rx_done <= 1'b0;

            case (state)
            IDLE: begin
                if (rx_sync_1 == 1'b0) begin // RX = 0, Start bit
                    tick_count <= 4'b0;
                    bit_count  <= 4'b0;
                    parity_err <= 1'b0;
                    state      <= START;
                end
            end 

            START: begin
                if(baud_tick) begin
                    if (tick_count == 4'd7) begin // middle of the start bit
                        if (rx_sync_1 == 1'b1) begin // RX goes 1, mean glitch
                            tick_count <= 4'd0;
                            state      <= IDLE;
                        end else begin
                            tick_count <= tick_count + 4'd1;
                        end
                    end else if (tick_count == 4'd15) begin // end of start bit
                        tick_count <= 4'd0;
                        state      <= DATA;
                    end else begin
                        tick_count <= tick_count + 4'd1;
                    end
                end
            end

            DATA: begin
                if (baud_tick) begin
                    if (tick_count == 4'd7) begin
                        rx_data_reg <= {rx_sync_1, rx_data_reg[7:1]}; // LSB first, shift from LEFT
                        tick_count  <= tick_count + 4'd1;
                    end else if (tick_count == 4'd15) begin // middle of data bit
                        tick_count <= 4'b0; 
                        if (bit_count < 4'd7) begin
                            bit_count <= bit_count + 4'd1;
                        end else begin 
                            // got bit is 8
                            bit_count <= 4'd0;
                            state     <= (parity_mode != PARITY_NONE) ? PARITY : STOP;
                        end
                    end else begin
                        tick_count <= tick_count + 4'd1;
                    end
                end
            end
    
            PARITY: begin
                if (baud_tick) begin
                    if (tick_count == 4'd7) begin
                        parity_bit_reg <= rx_sync_1;
                        tick_count     <= tick_count + 4'd1;
                    end else if (tick_count == 4'd15) begin
                        tick_count <= 4'd0;
                        parity_err <= (parity_bit_reg != parity_bit(rx_data_reg, parity_mode));
                        state      <= STOP;
                    end else begin
                        tick_count <= tick_count + 4'd1;
                    end
                end
            end

            STOP: begin
                if (baud_tick) begin
                    if (tick_count == 4'd15) begin // middle of stop bit
                        tick_count <= 4'd0;
                        if (stop_mode == STOP_2) begin
                            state <= STOP2;
                        end else begin
                            rx_done <= 1'b1;
                            rx_data <= rx_data_reg;
                            state   <= IDLE;
                        end
                    end else begin
                        tick_count <= tick_count + 4'd1;
                    end
                end
            end

            STOP2: begin
                if (baud_tick) begin
                    if (tick_count == 4'd15) begin
                        tick_count <= 4'd0;
                        rx_done    <= 1'b1;
                        rx_data    <= rx_data_reg;
                        state      <= IDLE;
                    end else begin
                        tick_count <= tick_count + 4'd1;
                    end
                end
            end
    
            default: state <= IDLE;
            endcase
        end
    end
endmodule
