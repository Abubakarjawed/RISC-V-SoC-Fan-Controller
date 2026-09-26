`timescale 1ns/1ps

module spi_engine (
    input  logic        PCLK,
    input  logic        PRESETn,
    input  logic        sclk_tick,   // baud tick from clock divider (bridge generates this)
    input  logic        enable,

    // TX FIFO interface (bridge/buffer side)
    input  logic        tx_fifo_empty,
    output logic        tx_fifo_rd_en,
    input  logic [7:0]  tx_fifo_rd_data,

    // RX FIFO interface (bridge/buffer side)
    input  logic        rx_fifo_full,
    output logic        rx_fifo_wr_en,
    output logic [7:0]  rx_fifo_wr_data,

    // physical SPI pins
    output logic        SCLK,
    output logic        MOSI,
    input  logic        MISO,
    output logic         SS_N
);

    logic [7:0] tx_shift;   // dedicated TX shift register (drives MOSI)
    logic [7:0] rx_shift;   // dedicated RX shift register (captures MISO)
    logic [3:0] bit_count;

    logic sclk;
    logic ss_n;

    typedef enum logic [1:0] {
        IDLE,
        LOAD,
        SHIFT_TOGGLE,
        STORE
    } spi_state_t;

    spi_state_t current_state, next_state;

    // ---- sequential ----
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            current_state <= IDLE;
            tx_shift      <= 8'h00;
            rx_shift      <= 8'h00;
            bit_count     <= 4'd0;
            sclk          <= 1'b0;
        end else begin
            current_state <= next_state;

            if (current_state == LOAD) begin
                tx_shift  <= tx_fifo_rd_data;
                bit_count <= 4'd0;
                sclk      <= 1'b0;
            end

            if (current_state == SHIFT_TOGGLE && sclk_tick) begin
                sclk <= ~sclk;

                if (!sclk) begin
                    // rising edge (0 -> 1): sample MISO into LSB, MSB-first shift-in
                    rx_shift <= {rx_shift[6:0], MISO};
                end else begin
                    // falling edge (1 -> 0): advance TX register for next bit
                    tx_shift  <= tx_shift << 1;
                    bit_count <= bit_count + 1'b1;
                end
            end
        end
    end

    // MOSI always reflects current MSB of tx_shift -> no off-by-one, D[0] gets sent correctly
    assign MOSI = tx_shift[7];
    assign SCLK = sclk;
    assign SS_N = ss_n;

    // ---- combinational ----
    always_comb begin
        next_state = current_state;

        tx_fifo_rd_en   = 1'b0;
        rx_fifo_wr_en   = 1'b0;
        rx_fifo_wr_data = 8'h00;
        ss_n            = 1'b1;

        case (current_state)
            IDLE: begin
                if (enable && !tx_fifo_empty) begin
                    next_state = LOAD;
                end
            end

            LOAD: begin
                ss_n          = 1'b0;
                tx_fifo_rd_en = 1'b1;
                next_state    = SHIFT_TOGGLE;
            end

            SHIFT_TOGGLE: begin
                ss_n = 1'b0;

                if (sclk_tick && sclk && bit_count == 4'd7) begin
                    next_state = STORE;
                end
            end

            STORE: begin
                ss_n            = 1'b0;
                rx_fifo_wr_en   = !rx_fifo_full;
                rx_fifo_wr_data = rx_shift;

                if (!tx_fifo_empty) begin
                    next_state = LOAD;
                end else begin
                    next_state = IDLE;
                end
            end

            default: next_state = IDLE;
        endcase
    end

endmodule
