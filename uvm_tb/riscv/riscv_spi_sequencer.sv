//=============================================================
// riscv_spi_sequencer.sv
//=============================================================
class riscv_spi_sequencer extends uvm_sequencer #(riscv_spi_seq_item);
    `uvm_component_utils(riscv_spi_sequencer)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass : riscv_spi_sequencer


//=============================================================
// riscv_spi_loopback_seq.sv
// Default sequence: keep the driver in pure loopback mode
// (MISO <= MOSI) for the whole test. This reproduces the
// original directed testbench's `assign MISO = MOSI;` slave
// model, just issued as a sequence item instead of a wire.
//=============================================================
class riscv_spi_loopback_seq extends uvm_sequence #(riscv_spi_seq_item);
    `uvm_object_utils(riscv_spi_loopback_seq)

    function new(string name = "riscv_spi_loopback_seq");
        super.new(name);
    endfunction

    task body();
        riscv_spi_seq_item item;
        item = riscv_spi_seq_item::type_id::create("item");
        start_item(item);
        item.miso_mode  = riscv_spi_seq_item::MISO_LOOPBACK;
        item.fixed_byte = 8'h00;
        finish_item(item);
    endtask
endclass : riscv_spi_loopback_seq


//=============================================================
// riscv_spi_fixed_byte_seq.sv
// Drives a fixed byte back on MISO regardless of MOSI, so a
// test can check the core correctly receives an arbitrary,
// non-loopback SPI slave response.
//=============================================================
class riscv_spi_fixed_byte_seq extends uvm_sequence #(riscv_spi_seq_item);
    `uvm_object_utils(riscv_spi_fixed_byte_seq)

    rand bit [7:0] byte_to_send = 8'h5A;

    function new(string name = "riscv_spi_fixed_byte_seq");
        super.new(name);
    endfunction

    task body();
        riscv_spi_seq_item item;
        item = riscv_spi_seq_item::type_id::create("item");
        start_item(item);
        item.miso_mode  = riscv_spi_seq_item::MISO_FIXED;
        item.fixed_byte = byte_to_send;
        finish_item(item);
    endtask
endclass : riscv_spi_fixed_byte_seq
