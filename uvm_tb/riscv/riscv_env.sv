//=============================================================
// riscv_env.sv
//=============================================================
class riscv_env extends uvm_env;
    `uvm_component_utils(riscv_env)

    riscv_spi_agent   spi_agent;
    riscv_scoreboard  sb;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        spi_agent = riscv_spi_agent::type_id::create("spi_agent", this);
        sb        = riscv_scoreboard::type_id::create("sb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        spi_agent.ap.connect(sb.spi_imp);
    endfunction

endclass : riscv_env
