//=============================================================
// riscv_spi_seq_item.sv
// Two uses of the same item:
//  - as a DRIVER item: tells the driver how to respond on MISO
//    for the next byte the DUT's spi_engine shifts out
//    (LOOPBACK: MISO <= MOSI bit-for-bit, or FIXED: drive a
//    programmed byte regardless of MOSI).
//  - as a MONITOR item: published after the monitor decodes a
//    completed 8-bit SPI beat, carrying what was actually seen
//    on MOSI (tx_byte) and MISO (rx_byte) during that beat.
//=============================================================
class riscv_spi_seq_item extends uvm_sequence_item;

    typedef enum { MISO_LOOPBACK, MISO_FIXED } miso_mode_e;

    // driver-facing fields
    rand miso_mode_e miso_mode = MISO_LOOPBACK;
    rand bit [7:0]   fixed_byte = 8'h00;

    // monitor-facing fields (filled in by the monitor, ignored by driver)
    bit [7:0] tx_byte;   // byte the core drove out on MOSI
    bit [7:0] rx_byte;   // byte the core sampled in on MISO
    time      t_start;
    time      t_end;

    `uvm_object_utils_begin(riscv_spi_seq_item)
        `uvm_field_enum(miso_mode_e, miso_mode, UVM_ALL_ON)
        `uvm_field_int(fixed_byte,           UVM_ALL_ON)
        `uvm_field_int(tx_byte,              UVM_ALL_ON | UVM_NOPACK)
        `uvm_field_int(rx_byte,              UVM_ALL_ON | UVM_NOPACK)
    `uvm_object_utils_end

    function new(string name = "riscv_spi_seq_item");
        super.new(name);
    endfunction

    function string convert2str();
        return $sformatf("mode=%s fixed=0x%0h tx=0x%0h rx=0x%0h",
                          miso_mode.name(), fixed_byte, tx_byte, rx_byte);
    endfunction

endclass : riscv_spi_seq_item
