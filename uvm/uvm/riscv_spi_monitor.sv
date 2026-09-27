//=============================================================
// riscv_spi_monitor.sv
// Passive bus monitor: watches SCLK/MOSI/MISO/SS_N and, every
// time it sees 8 SCLK rising edges inside a single SS_N-low
// window, reconstructs the MSB-first byte that went out on MOSI
// and the byte that came back on MISO, then publishes one
// riscv_spi_seq_item per completed beat on its analysis port.
//
// This mirrors spi_engine.sv's own protocol exactly (see
// rtl/soc/spi_engine.sv): sample MISO on the 0->1 SCLK edge,
// MOSI is stable (driven from tx_shift[7]) at that same edge.
//=============================================================
class riscv_spi_monitor extends uvm_monitor;
    `uvm_component_utils(riscv_spi_monitor)

    virtual riscv_spi_if vif;
    uvm_analysis_port #(riscv_spi_seq_item) ap;
    local bit sclk_q = 1'b0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual riscv_spi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "riscv_spi_monitor: virtual interface not set in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        bit [7:0] tx_acc, rx_acc;
        int       nbits;
        bit       in_frame;
        time      t_start;

        in_frame = 1'b0;
        nbits    = 0;

        forever begin
            @(posedge vif.PCLK);

            if (vif.SS_N) begin
                // slave deselected: any partial frame is abandoned
                in_frame = 1'b0;
                nbits    = 0;
            end else begin
                // rising edge of the DUT-generated SCLK, sampled
                // through the PCLK domain -> exactly when the DUT
                // itself latches MISO into rx_shift.
                if (vif.SCLK && !sclk_q) begin
                    if (!in_frame) begin
                        in_frame = 1'b1;
                        nbits    = 0;
                        t_start  = $time;
                    end
                    tx_acc = {tx_acc[6:0], vif.MOSI};
                    rx_acc = {rx_acc[6:0], vif.MISO};
                    nbits++;

                    if (nbits == 8) begin
                        riscv_spi_seq_item item = riscv_spi_seq_item::type_id::create("item");
                        item.tx_byte = tx_acc;
                        item.rx_byte = rx_acc;
                        item.t_start = t_start;
                        item.t_end   = $time;
                        `uvm_info("SPI_MON",
                                  $sformatf("beat complete: %s", item.convert2str()),
                                  UVM_MEDIUM)
                        ap.write(item);
                        in_frame = 1'b0;
                        nbits    = 0;
                    end
                end
            end
            sclk_q = vif.SCLK;
        end
    endtask

endclass : riscv_spi_monitor
