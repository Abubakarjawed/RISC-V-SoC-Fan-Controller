`timescale 1ns/1ps
package apb_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // -----------------------------------------------------------------
    // Transaction (sequence item)
    // -----------------------------------------------------------------
    class apb_txn extends uvm_sequence_item;
        rand bit        write;      // 1 = write, 0 = read
        rand bit [31:0] addr;
        rand bit [31:0] wdata;
             bit [31:0] rdata;      // driver/monitor fills this in
             bit        slverr;     // observed PSLVERR

        `uvm_object_utils_begin(apb_txn)
            `uvm_field_int(write,  UVM_ALL_ON)
            `uvm_field_int(addr,   UVM_ALL_ON)
            `uvm_field_int(wdata,  UVM_ALL_ON)
            `uvm_field_int(rdata,  UVM_ALL_ON)
            `uvm_field_int(slverr, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "apb_txn");
            super.new(name);
        endfunction

        function string convert2string();
            return $sformatf("%s addr=0x%0h wdata=0x%0h rdata=0x%0h slverr=%0b",
                              write ? "WRITE" : "READ ", addr, wdata, rdata, slverr);
        endfunction
    endclass

    // -----------------------------------------------------------------
    // Sequencer
    // -----------------------------------------------------------------
    typedef uvm_sequencer #(apb_txn) apb_sequencer;


    class apb_driver extends uvm_driver #(apb_txn);
        `uvm_component_utils(apb_driver)

        virtual apb_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif))
                `uvm_fatal("APB_DRV", "virtual apb_if not set in config_db")
        endfunction

        task run_phase(uvm_phase phase);
            // reset ke doran idle rakho
            vif.PSEL     <= 1'b0;
            vif.PENABLE  <= 1'b0;
            vif.PWRITE   <= 1'b0;
            vif.PADDR    <= '0;
            vif.PWDATA   <= '0;
            wait (vif.PRESETn === 1'b1);

            forever begin
                apb_txn req;
                seq_item_port.get_next_item(req);
                if (req.write) drive_write(req);
                else            drive_read(req);
                seq_item_port.item_done();
            end
        endtask

        task automatic drive_write(apb_txn req);
            @(negedge vif.PCLK);
            vif.PSEL    <= 1'b1;
            vif.PENABLE <= 1'b0;
            vif.PWRITE  <= 1'b1;
            vif.PADDR   <= req.addr;
            vif.PWDATA  <= req.wdata;
            @(posedge vif.PCLK);
            @(negedge vif.PCLK);
            vif.PENABLE <= 1'b1;
            @(posedge vif.PCLK);
            while (vif.PREADY !== 1'b1) @(posedge vif.PCLK);
            req.slverr = vif.PSLVERR;
            @(negedge vif.PCLK);
            vif.PSEL    <= 1'b0;
            vif.PENABLE <= 1'b0;
        endtask

        task automatic drive_read(apb_txn req);
            @(negedge vif.PCLK);
            vif.PSEL    <= 1'b1;
            vif.PENABLE <= 1'b0;
            vif.PWRITE  <= 1'b0;
            vif.PADDR   <= req.addr;
            @(posedge vif.PCLK);
            @(negedge vif.PCLK);
            vif.PENABLE <= 1'b1;
            @(posedge vif.PCLK);
            while (vif.PREADY !== 1'b1) @(posedge vif.PCLK);
            req.rdata  = vif.PRDATA;
            req.slverr = vif.PSLVERR;
            @(negedge vif.PCLK);
            vif.PSEL    <= 1'b0;
            vif.PENABLE <= 1'b0;
        endtask
    endclass

    class apb_monitor extends uvm_monitor;
        `uvm_component_utils(apb_monitor)

        virtual apb_if vif;
        uvm_analysis_port #(apb_txn) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif))
                `uvm_fatal("APB_MON", "virtual apb_if not set in config_db")
        endfunction

        task run_phase(uvm_phase phase);
            forever begin
                apb_txn tr;
                @(posedge vif.PCLK);
                if (vif.PSEL && vif.PENABLE && vif.PREADY) begin
                    tr        = apb_txn::type_id::create("tr");
                    tr.write  = vif.PWRITE;
                    tr.addr   = vif.PADDR;
                    tr.wdata  = vif.PWDATA;
                    tr.rdata  = vif.PRDATA;
                    tr.slverr = vif.PSLVERR;
                    `uvm_info("APB_MON", tr.convert2string(), UVM_HIGH)
                    ap.write(tr);
                end
            end
        endtask
    endclass

    // -----------------------------------------------------------------
    // Agent
    // -----------------------------------------------------------------
    class apb_agent extends uvm_agent;
        `uvm_component_utils(apb_agent)

        apb_driver    driver;
        apb_sequencer sequencer;
        apb_monitor   monitor;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            monitor = apb_monitor::type_id::create("monitor", this);
            if (get_is_active() == UVM_ACTIVE) begin
                driver    = apb_driver::type_id::create("driver", this);
                sequencer = apb_sequencer::type_id::create("sequencer", this);
            end
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            if (get_is_active() == UVM_ACTIVE)
                driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
    endclass


    class apb_base_sequence extends uvm_sequence #(apb_txn);
        `uvm_object_utils(apb_base_sequence)

        function new(string name = "apb_base_sequence");
            super.new(name);
        endfunction

        task automatic apb_write(bit [31:0] addr, bit [31:0] data);
            apb_txn req = apb_txn::type_id::create("req");
            start_item(req);
            req.write = 1'b1;
            req.addr  = addr;
            req.wdata = data;
            finish_item(req);
        endtask

        task automatic apb_read(bit [31:0] addr, output bit [31:0] data);
            apb_txn req = apb_txn::type_id::create("req");
            start_item(req);
            req.write = 1'b0;
            req.addr  = addr;
            finish_item(req);
            data = req.rdata;
        endtask
    endclass

endpackage
