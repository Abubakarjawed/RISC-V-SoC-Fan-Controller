`timescale 1ns/1ps

module apb_slave_fsm_sram (
    input  logic       PCLK,
    input  logic       PRESETn,
    input  logic       PSEL,
    input  logic       PENABLE,
    input  logic       PWRITE,
    input  logic [7:0] PADDR,
    input  logic [7:0] PWDATA,

    output logic [7:0] PRDATA,
    output logic       PREADY,
    output logic       PSLVERR,

    // ---- sram_engine side ----
    output logic        mem_wr_en,
    output logic [7:0]  mem_addr,
    output logic [7:0]  mem_wr_data,
    input  logic [7:0]  mem_rd_data
);

    typedef enum logic [1:0] {
        IDLE   = 2'b00,
        SETUP  = 2'b01,
        ACCESS = 2'b10
    } apb_state_t;

    apb_state_t current_state, next_state;

    logic apb_write;
    logic apb_read;
    logic apb_done;

    assign apb_done  = (current_state == ACCESS) && PSEL && PENABLE && PREADY;
    assign apb_write = apb_done && PWRITE;
    assign apb_read  = apb_done && !PWRITE;

    assign PSLVERR = 1'b0;

    // ---------------------------------------------------------------
    // APB FSM - no wait states needed (combinational memory read)
    // ---------------------------------------------------------------
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) current_state <= IDLE;
        else          current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;
        PREADY = 1'b0;

        case (current_state)
            IDLE: begin
                if (PSEL) next_state = SETUP;
            end

            SETUP: begin
                next_state = ACCESS;
            end

            ACCESS: begin
                if (!PSEL) begin
                    next_state = IDLE;
                end else if (!PENABLE) begin
                    PREADY = 1'b0;
                    next_state = ACCESS;
                end else begin
                    PREADY = 1'b1;
                    next_state = IDLE;
                end
            end

            default: next_state = IDLE;
        endcase
    end

    // ---------------------------------------------------------------
    // memory-side connections
    // ---------------------------------------------------------------
    assign mem_addr    = PADDR;
    assign mem_wr_data = PWDATA;
    assign mem_wr_en   = apb_write;

    // ---------------------------------------------------------------
    // read mux
    // ---------------------------------------------------------------
    always_comb begin
        PRDATA = 8'h00;
        if (current_state == ACCESS && !PWRITE) begin
            PRDATA = mem_rd_data;
        end
    end

endmodule
