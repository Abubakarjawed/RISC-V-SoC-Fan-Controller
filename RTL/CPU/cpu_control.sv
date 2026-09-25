`timescale 1ns/1ps
//=============================================================
// cpu_control.sv
// This core executes one instruction per clock cycle as long as
// data-memory / instruction-memory are combinationally-read
// on-chip SRAM. Memory-mapped peripherals (SPI/UART/PWM behind
// the APB bridge) need several clock cycles per access, so this
// block stalls the PC and gates the register-file write / memory
// write strobes while an APB transaction is outstanding.
//=============================================================
module cpu_control (
    input  logic clk,
    input  logic rst_n,

    input  logic mem_read,        // from decoder: current instr is a LOAD
    input  logic mem_write,       // from decoder: current instr is a STORE
    input  logic is_periph_addr,  // effective address decodes to the peripheral region

    input  logic periph_done,     // pulses 1 for the cycle the APB txn completes

    output logic periph_req,      // level-held request to the APB bridge
    output logic pc_stall,        // hold PC (and instruction) this cycle
    output logic mem_stage_valid  // 1 = ok to commit reg/mem writes this cycle
);

    typedef enum logic [0:0] {
        S_IDLE = 1'b0,
        S_WAIT = 1'b1
    } ctrl_state_t;

    ctrl_state_t state_q, state_d;

    logic need_periph;
    assign need_periph = (mem_read || mem_write) && is_periph_addr;

    always_comb begin
        state_d = state_q;
        case (state_q)
            S_IDLE: begin
                if (need_periph && !periph_done) begin
                    state_d = S_WAIT;
                end
            end
            S_WAIT: begin
                if (periph_done) begin
                    state_d = S_IDLE;
                end
            end
            default: state_d = S_IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= S_IDLE;
        end else begin
            state_q <= state_d;
        end
    end

    // Request stays asserted from the first cycle we see the access
    // until the bridge reports completion.
    assign periph_req = (state_q == S_WAIT) || (state_q == S_IDLE && need_periph);

    // Stall the PC (and therefore the instruction held at the decode
    // inputs, since imem address is driven by PC) until the access
    // is done. A same-cycle periph_done means no stall is needed.
    assign pc_stall = periph_req && !periph_done;

    // Register-file / data-memory writes should only commit once the
    // access (if any) is actually complete.
    assign mem_stage_valid = !need_periph || periph_done || (state_q == S_WAIT && periph_done);

endmodule
