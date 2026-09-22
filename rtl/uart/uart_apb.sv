`timescale 1ns/1ps

import uart_pkg::*;

module uart_apb (
    input  logic                     PCLK,
    input  logic                     PRESETn,
    input  logic                     PSEL,
    input  logic                     PENABLE,
    input  logic                     PWRITE,
    input  logic [ADDR_WIDTH_32-1:0] PADDR,
    input  logic [DATA_WIDTH_32-1:0] PWDATA,
    
    // Outputs to APB Bus
    output logic [DATA_WIDTH_32-1:0] PRDATA,
    output logic                     PREADY,
    output logic                     PSLVERR,

    // uart pins
    input  logic uart_rx,
    output logic uart_tx
);
    // Register address offset
    localparam logic [DATA_WIDTH_8-1:0] TX_DATA = 8'h00;
    localparam logic [DATA_WIDTH_8-1:0] RX_DATA = 8'h04;
    localparam logic [DATA_WIDTH_8-1:0] STATUS  = 8'h08;
    localparam logic [DATA_WIDTH_8-1:0] CTRL    = 8'h0C;
    
    // Uart internal signals
    logic tx_start;
    logic tx_ready;
    logic [DATA_WIDTH_8-1:0] rx_data;
    logic uart_rx_done;
    logic parity_err;

    logic tx_busy;
    logic rx_error; 
    logic rx_valid;

    assign tx_busy = ~tx_ready;
    
    // Helper signals
    logic addr_tx;
    logic addr_rx;
    logic addr_status;
    logic addr_ctrl;

    assign addr_tx     = (PADDR [ADDR_WIDTH_8-1:0] == TX_DATA);
    assign addr_rx     = (PADDR [ADDR_WIDTH_8-1:0] == RX_DATA);
    assign addr_status = (PADDR [ADDR_WIDTH_8-1:0] == STATUS);
    assign addr_ctrl   = (PADDR [ADDR_WIDTH_8-1:0] == CTRL);

    assign PSLVERR     = 1'b0;

    // Internal signals
    logic [DATA_WIDTH_8-1:0] tx_data_reg_value;
    logic [DATA_WIDTH_8-1:0] rx_data_reg_value;
    logic [DATA_WIDTH_8-1:0] ctrl_reg_value;
    logic [DATA_WIDTH_8-1:0] status_reg_value;

    assign status_reg_value = {5'b00000, tx_busy, rx_valid, rx_error};

    // FSM Machine
    typedef enum logic [1:0] {
        IDLE   = 2'b00,
        SETUP  = 2'b01,
        ACCESS = 2'b10
    } apb_state_t;

    apb_state_t current_state, next_state;

    // APB write/read
    logic apb_done;
    logic apb_write;
    logic apb_read;
    logic apb_read_rx;

    assign apb_done     = (current_state == ACCESS) && PSEL && PENABLE && PREADY;
    assign apb_write    = apb_done && PWRITE;
    assign apb_read     = apb_done && !PWRITE;
    assign apb_read_rx  = apb_read && addr_rx;

    // Sequential logic
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // State transition logic
    always_comb begin
        next_state = current_state;
        PREADY = 1'b0;
        
        case (current_state)
            IDLE: begin
                if (PSEL) begin
                next_state = SETUP;  
                end
            end
            
            SETUP: begin
                if (!PSEL) begin
                    next_state = IDLE;
                end else begin
                    next_state = ACCESS; 
                end
            end
            
            ACCESS: begin
                if (!PSEL) begin
                    next_state = IDLE;
                end else if (!PENABLE) begin
                    next_state = SETUP;
                end else begin
                    PREADY = 1'b1;
                    next_state = IDLE;
                end
            end

            default: next_state = IDLE;
        endcase
    end

    // Register write control 
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            ctrl_reg_value    <= '0;
            tx_data_reg_value <= '0;
            tx_start          <= 1'b0;
        end else begin
            tx_start <= 1'b0;

            if (apb_write) begin
                if (addr_ctrl) begin
                    ctrl_reg_value    <= PWDATA;
                end else if (addr_tx) begin
                    tx_data_reg_value <= PWDATA;
                    tx_start          <= 1'b1;
                end
            end
        end
    end

    // Register read control
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            rx_data_reg_value <= 'h0;
            rx_error          <= 1'b0;
            rx_valid          <= 1'b0;
        end else begin
            if (uart_rx_done) begin
                rx_data_reg_value <= rx_data;
                rx_error          <= parity_err;
                rx_valid          <= 1'b1;
            end else if (apb_read_rx) begin
                rx_valid          <= 1'b0;
            end
        end
    end

    // APB read data status
    always_comb begin 
        PRDATA = '0;

        if (apb_read) begin
            case (PADDR [ADDR_WIDTH_8-1:0])
                TX_DATA: PRDATA = {24'h0, tx_data_reg_value};
                RX_DATA: PRDATA = {24'h0, rx_data_reg_value};
                STATUS : PRDATA = {24'h0, status_reg_value};
                CTRL   : PRDATA = {24'h0, ctrl_reg_value};
                default: PRDATA = '0;
            endcase
        end
    end

    uart_top uart_top_inst (
        .clk         (PCLK),
        .rst_n       (PRESETn),
        .parity_mode (parity_e'(ctrl_reg_value[1:0])),
        .stop_mode   (stop_e'(ctrl_reg_value[2])),
        .tx_data     (tx_data_reg_value),
        .tx_start    (tx_start),
        .tx_ready    (tx_ready),
        .uart_tx     (uart_tx),
        .uart_rx     (uart_rx),
        .rx_data     (rx_data), 
        .rx_done     (uart_rx_done),
        .parity_err  (parity_err)
    );

endmodule

