//=============================================================
// riscv_spi_agent.sv
//=============================================================
class riscv_spi_agent extends uvm_agent;
    `uvm_component_utils(riscv_spi_agent)

    riscv_spi_sequencer sqr;
    riscv_spi_driver     drv;
    riscv_spi_monitor    mon;

    uvm_analysis_port #(riscv_spi_seq_item) ap; // pass-through to env/scoreboard

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = riscv_spi_monitor::type_id::create("mon", this);
        ap  = new("ap", this);

        if (get_is_active() == UVM_ACTIVE) begin
            sqr = riscv_spi_sequencer::type_id::create("sqr", this);
            drv = riscv_spi_driver::type_id::create("drv", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        mon.ap.connect(ap);
        if (get_is_active() == UVM_ACTIVE)
            drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction

endclass : riscv_spi_agent
