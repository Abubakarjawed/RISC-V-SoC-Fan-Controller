`timescale 1ns/1ps
//=============================================================
// cpu_apb_bridge.sv
// APB3 master bridge between the RV32I core's generic data bus
// and the team's shared 32-bit APB fabric (apb_interconnect ->
// spi_soc_top / pwm_soc_top / sram_soc_top / uart, all of which
// use 32-bit PADDR/PWDATA/PRDATA -- only the low byte of PADDR
// and PWDATA is actually meaningful to any one peripheral, but
// the bus itself is word-wide so it matches apb_interconnect's
// master port).
//
// UPDATED (integration pass): PADDR/PWDATA/PRDATA widened from
// 8 to 32 bits. Previously this bridge truncated dmem_addr and
// dmem_wdata down to their low byte before driving the (8-bit)
// apb_slave_fsm directly; now the full 32-bit address/data is
// passed straight through to apb_interconnect, which needs the
// upper bits to pick the right slave. No peripheral register is
// wider than a byte, so each peripheral wrapper still only looks
// at PADDR[7:0]/PWDATA[7:0] internally -- this bridge does not
// need to know that.
//
// Peripheral registers are byte-wide, so software accesses them
// with LB/LBU/SB at the word-aligned offsets defined in the
// peripheral's register map (address[1:0] == 2'b00).
//
// While a request is outstanding, dmem_addr/dmem_wdata/dmem_write
// from the core are held stable by cpu_control's pc_stall, so
// they can be driven onto PADDR/PWDATA/PWRITE combinationally -
// no need to latch them.
//=============================================================
module cpu_apb_bridge (
    input  logic        PCLK,
    input  logic        PRESETn,

    // ---- core-side generic bus ----
    input  logic         is_periph_addr,
    input  logic         dmem_read,
    input  logic         dmem_write,
    input  logic [31:0]  dmem_addr,
    input  logic [31:0]  dmem_wdata,
    output logic [31:0]  periph_rdata,
    output logic          periph_done,

    // ---- APB master port (32-bit, matches apb_interconnect) ----
    output logic        PSEL,
    output logic        PENABLE,
    output logic        PWRITE,
    output logic [31:0] PADDR,
    output logic [31:0] PWDATA,
    input  logic [31:0] PRDATA,
    input  logic        PREADY,
    input  logic        PSLVERR
);

    typedef enum logic [1:0] {
        B_IDLE  = 2'b00,
        B_SETUP = 2'b01,
        B_ACCESS= 2'b10
    } bridge_state_t;

    bridge_state_t state_q, state_d;

    logic req;
    assign req = is_periph_addr && (dmem_read || dmem_write);

    always_comb begin
        state_d = state_q;
        case (state_q)
            B_IDLE : begin
                if (req) state_d = B_SETUP;
                else     state_d = B_IDLE;
            end
            B_SETUP: state_d = B_ACCESS;
            B_ACCESS: begin
                if (PREADY) state_d = B_IDLE;
                else        state_d = B_ACCESS;
            end
            default: state_d = B_IDLE;
        endcase
    end

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) state_q <= B_IDLE;
        else          state_q <= state_d;
    end

    assign PSEL    = (state_q != B_IDLE);
    assign PENABLE = (state_q == B_ACCESS);
    assign PWRITE  = dmem_write;
    assign PADDR   = dmem_addr;    // full system address; apb_interconnect decodes it
    assign PWDATA  = dmem_wdata;   // full word; each peripheral only reads PWDATA[7:0]

    assign periph_done  = (state_q == B_ACCESS) && PREADY;
    assign periph_rdata = PRDATA;  // already 32-bit, no zero-extend needed

    // PSLVERR is currently unused by the core (no fault register yet).
    // apb_interconnect DOES assert it on an unmapped address, and the
    // peripherals themselves still tie it to 0 -- see riscv_soc_top.sv
    // for where this would eventually feed a status/exception path.

endmodule
