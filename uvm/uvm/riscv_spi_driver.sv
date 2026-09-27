//=============================================================
// riscv_spi_driver.sv
// Owns the only pin the testbench is allowed to drive: MISO.
// Also generates PRESETn, since bringing the DUT out of reset is
// this agent's job in this simple, single-agent environment.
//
// Two response modes, selected per sequence item:
//   MISO_LOOPBACK - MISO tracks MOSI combinationally (models an
//                   SPI slave that echoes whatever it receives -
//                   this is what the original directed TB's
//                   `assign MISO = MOSI;` did).
//   MISO_FIXED    - MISO shifts out a fixed byte, MSB first,
//                   synchronized to SCLK edges, independent of
//                   MOSI.
//=============================================================
class riscv_spi_driver extends uvm_driver #(riscv_spi_seq_item);
    `uvm_component_utils(riscv_spi_driver)

    virtual riscv_spi_if vif;

    protected riscv_spi_seq_item::miso_mode_e cur_mode  = riscv_spi_seq_item::MISO_LOOPBACK;
    protected bit [7:0]                       cur_fixed = 8'h00;
    protected bit [2:0]                       bit_idx   = 3'd0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual riscv_spi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "riscv_spi_driver: virtual interface not set in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        fork
            reset_gen();
            config_listener();
            track_bit_index();
            drive_miso();
        join_none
    endtask

    // Active-low reset pulse. Runs once at the start of the test;
    // held here (rather than in tb_top) so the sequence of "assert
    // reset, wait N cycles, release" is visible/traceable as agent
    // behaviour like any other stimulus.
    task reset_gen();
        vif.PRESETn = 1'b0;
        repeat (5) @(posedge vif.PCLK);
        vif.PRESETn = 1'b1;
        `uvm_info("SPI_DRV", "PRESETn released", UVM_MEDIUM)
    endtask

    // Pulls response-mode items from the sequencer. Each item just
    // (re)configures how MISO behaves from now on; there's no
    // per-byte handshake to wait for, so items complete immediately.
    task config_listener();
        riscv_spi_seq_item req;
        forever begin
            seq_item_port.get_next_item(req);
            cur_mode  = req.miso_mode;
            cur_fixed = req.fixed_byte;
            `uvm_info("SPI_DRV", $sformatf("mode=%s fixed=0x%0h",
                      cur_mode.name(), cur_fixed), UVM_HIGH)
            seq_item_port.item_done();
        end
    endtask

    // Bit index into cur_fixed, MSB first; resets whenever the DUT
    // deselects the slave (SS_N high).
    task track_bit_index();
        bit_idx = 3'd0;
        forever begin
            @(vif.SS_N or posedge vif.SCLK);
            if (vif.SS_N)
                bit_idx = 3'd0;
            else if (vif.SCLK)
                bit_idx = bit_idx + 3'd1;
        end
    endtask

    // Combinational-style MISO drive: re-evaluates immediately on
    // any relevant change, same delta-cycle behaviour as a plain
    // `assign`, so it never adds latency relative to SCLK edges.
    task drive_miso();
        vif.MISO = 1'b0;
        forever begin
            @(vif.MOSI or vif.SS_N or vif.SCLK or cur_mode or cur_fixed or bit_idx);
            unique case (cur_mode)
                riscv_spi_seq_item::MISO_LOOPBACK: vif.MISO = vif.MOSI;
                riscv_spi_seq_item::MISO_FIXED:    vif.MISO = cur_fixed[7 - bit_idx];
                default:                           vif.MISO = 1'b0;
            endcase
        end
    endtask

endclass : riscv_spi_driver
