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


    property p_penable_requires_psel;
        @(posedge PCLK) disable iff (!PRESETn)
        PENABLE |-> PSEL;
    endproperty

    a_penable_requires_psel: assert property (p_penable_requires_psel)
        else $error("[SVA FAIL] APB Protocol Violation: PENABLE active without PSEL!");

    property p_access_signals_stable;
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && PENABLE && !PREADY) |=> ($stable(PADDR) && $stable(PWRITE) && $stable(PWDATA));
    endproperty

    a_access_signals_stable: assert property (p_access_signals_stable)
        else $error("[SVA FAIL] APB Protocol Violation: Control signals changed while waiting for PREADY!");


    property p_bus_hold_wait_pready;
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && PENABLE && !PREADY) |=> (PSEL && PENABLE);
    endproperty

    a_bus_hold_wait_pready: assert property (p_bus_hold_wait_pready)
        else $error("[SVA FAIL] APB Protocol Violation: PSEL or PENABLE dropped before PREADY completed!");


    property p_penable_drop_after_transfer;
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && PENABLE && PREADY) |=> !PENABLE;
    endproperty

    a_penable_drop_after_transfer: assert property (p_penable_drop_after_transfer)
        else $error("[SVA FAIL] APB Protocol Violation: PENABLE stayed high after transfer completed!");

endmodule

bind soc_top apb_assertions #(
    .ADDR_WIDTH(32),
    .DATA_WIDTH(32)
) u_apb_assertions (
    .PCLK    (PCLK),
    .PRESETn (PRESETn),
    .PSEL    (riscv_soc_top_inst.PSEL),
    .PENABLE (riscv_soc_top_inst.PENABLE),
    .PWRITE  (riscv_soc_top_inst.PWRITE),
    .PADDR   (riscv_soc_top_inst.PADDR),
    .PWDATA  (riscv_soc_top_inst.PWDATA),
    .PRDATA  (riscv_soc_top_inst.PRDATA),
    .PREADY  (riscv_soc_top_inst.PREADY),
    .PSLVERR (riscv_soc_top_inst.PSLVERR)
);
