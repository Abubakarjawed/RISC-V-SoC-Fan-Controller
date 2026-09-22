import uart_pkg::*;

module transmitter (
    input  logic                    clk,
    input  logic                    rst_n,  
    input  logic                    baud_tick,
    input  logic [DATA_WIDTH_8-1:0] tx_data,
    input  logic                    tx_start,
    input  parity_e                 parity_mode,
    input  stop_e                   stop_mode,
    output logic                    tx_pin,
    output logic                    tx_ready
);
        
    logic [3:0] tick_count; // 4 bit counter
    logic [3:0] bit_count;
    logic [DATA_WIDTH_8-1:0] tx_data_reg;
    logic [DATA_WIDTH_8-1:0] tx_data_original;

    state_t state;

    always_ff @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin
            state            <= IDLE;
            tx_pin           <= 1'b1;
            tx_ready         <= 1'b1;
            tick_count       <= 4'd0;
            bit_count        <= 4'd0;
            tx_data_reg      <= '0;
            tx_data_original <= '0;
        end else begin
            case (state)
                IDLE: begin
                    tx_pin   <= 1'b1;
                    tx_ready <= 1'b1; // indicate for next ready transmition
                    if (tx_start == 1'b1) begin
                        tx_data_reg      <= tx_data; 
                        tx_data_original <= tx_data; 
                        tick_count       <= 4'd0;
                        bit_count        <= 4'd0;
                        state            <= START;
                    end
                end 

                START: begin
                    tx_pin   <= 1'b0;
                    tx_ready <= 1'b0;
                    if (baud_tick == 1'b1) begin
                        if (tick_count == 4'd15) begin
                            tick_count <= 4'd0;
                            state      <= DATA;
                        end else begin
                            tick_count <= tick_count + 4'd1;
                        end
                    end
                end

                DATA: begin
                    tx_pin <= tx_data_reg[0];
                    if (baud_tick == 1'b1) begin
                        tick_count <= tick_count + 4'd1;
                        if (tick_count == 4'd15) begin
                            tx_data_reg <= {1'b0, tx_data_reg[7:1]};
                            tick_count  <= 4'd0;
                            if (bit_count < 4'd7) begin
                                bit_count <= bit_count + 4'd1;
                            end else if (bit_count == 4'd7) begin
                                bit_count <= 4'd0;
                                state     <= (parity_mode != PARITY_NONE) ? PARITY : STOP;
                            end
                        end
                    end
                end

                PARITY: begin
                    tx_pin <= parity_bit(tx_data_original, parity_mode);
                    if (baud_tick == 1'b1) begin
                        tick_count <= tick_count + 4'd1;
                        if (tick_count == 4'd15) begin
                            tick_count <= 4'd0;
                            state      <= STOP;
                        end
                    end
                end

                STOP: begin
                    tx_pin <= 1'b1; 
                    if (baud_tick == 1'b1) begin
                        tick_count <= tick_count + 4'd1;
                        if (tick_count == 4'd15) begin
                            if (stop_mode == STOP_2) begin
                                state <= STOP2;
                            end else begin
                                tx_ready <= 1'b1;
                                state    <= IDLE;
                            end
                        end
                    end
                end

                STOP2: begin
                    tx_pin <= 1'b1;
                    if (baud_tick == 1'b1) begin
                        tick_count <= tick_count + 4'd1;
                        if (tick_count == 4'd15) begin
                            tick_count <= 4'd0;
                            tx_ready   <= 1'b1;
                            state      <= IDLE;
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
