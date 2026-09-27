`timescale 1ns/1ps

module apb_assertions #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input logic                  PCLK,
    input logic                  PRESETn,
    input logic                  PSEL,
    input logic                  PENABLE,
    input logic                  PWRITE,
    input logic [ADDR_WIDTH-1:0] PADDR,
    input logic [DATA_WIDTH-1:0] PWDATA,
    input logic [DATA_WIDTH-1:0] PRDATA,
    input logic                  PREADY,
    input logic                  PSLVERR
);

    // 1. Setup Phase to Access Phase Transition
    // Rule: When PSEL rises without PENABLE, PENABLE must rise in the next cycle.
    property p_setup_to_access;
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && !PENABLE) |=> PENABLE;
    endproperty

    a_setup_to_access: assert property (p_setup_to_access)
        else $error("[SVA FAIL] APB Protocol Violation: PENABLE did not rise 1 cycle after PSEL setup phase!");

    // 2. PENABLE Requires PSEL
    // Rule: PENABLE can never be high unless PSEL is also asserted.
    property p_penable_requires_psel;
        @(posedge PCLK) disable iff (!PRESETn)
        PENABLE |-> PSEL;
    endproperty

    a_penable_requires_psel: assert property (p_penable_requires_psel)
        else $error("[SVA FAIL] APB Protocol Violation: PENABLE active without PSEL!");

    // 3. Control & Address Stability During Access Phase
    // Rule: While waiting for PREADY in access phase, PADDR, PWRITE, and PWDATA must remain stable.
    property p_access_signals_stable;
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && PENABLE && !PREADY) |=> ($stable(PADDR) && $stable(PWRITE) && $stable(PWDATA));
    endproperty

    a_access_signals_stable: assert property (p_access_signals_stable)
        else $error("[SVA FAIL] APB Protocol Violation: Control signals changed while waiting for PREADY!");

    // 4. Bus Hold During Backpressure
    // Rule: While PREADY is low in the access phase, both PSEL and PENABLE must remain high.
    property p_bus_hold_wait_pready;
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && PENABLE && !PREADY) |=> (PSEL && PENABLE);
    endproperty

    a_bus_hold_wait_pready: assert property (p_bus_hold_wait_pready)
        else $error("[SVA FAIL] APB Protocol Violation: PSEL or PENABLE dropped before PREADY completed!");

    // 5. Access Phase Completion
    // Rule: Once PREADY goes high during access phase, PENABLE must drop on the next cycle.
    property p_penable_drop_after_transfer;
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && PENABLE && PREADY) |=> !PENABLE;
    endproperty

    a_penable_drop_after_transfer: assert property (p_penable_drop_after_transfer)
        else $error("[SVA FAIL] APB Protocol Violation: PENABLE stayed high after transfer completed!");

endmodule
