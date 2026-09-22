import uart_pkg::*;

module baud_generator (
    input  logic clk,
    input  logic rst_n,
    output logic baud_tick
);

    localparam int unsigned TICK_DIVISOR = CLK_HZ / (BAUD_RATE * 16);
    localparam int unsigned COUNTER_W = (TICK_DIVISOR <= 1) ? 1 : $clog2(TICK_DIVISOR);
    logic [COUNTER_W-1:0] counter;

    initial begin
        assert (TICK_DIVISOR > 0)
            else $error("CLK_HZ must be at least BAUD_RATE * 16");
    end

    always_ff @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin
            counter   <= 'd0;
            baud_tick <= 1'b0;
        end else begin
            if (counter == TICK_DIVISOR - 1) begin
                baud_tick <= 1'b1;
                counter   <= 'd0;
            end else begin
                baud_tick <= 1'b0;
                counter   <= counter + 1'b1;
            end
        end
    end
endmodule
