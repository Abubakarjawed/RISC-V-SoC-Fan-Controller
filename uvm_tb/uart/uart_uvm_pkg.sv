`timescale 1ns/1ps

package uart_uvm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Register Map Offsets
    localparam bit [7:0] UART_TX_DATA = 8'h00; // Write byte to send
    localparam bit [7:0] UART_RX_DATA = 8'h04; // Read received byte
    localparam bit [7:0] UART_STATUS  = 8'h08; // [0]=rx_err, [1]=rx_valid, [2]=tx_busy
    localparam bit [7:0] UART_CTRL    = 8'h0C; // Control register

    // Sequence Item
    class uart_seq_item extends uvm_sequence_item;
        rand bit [31:0] addr;
        rand bit [31:0] wdata;
            bit [31:0] rdata;
        rand bit        write;

        // Control & Status Decoded Fields (for coverage & scoreboard)
        bit rx_error;
        bit rx_valid;
        bit tx_busy;

        `uvm_object_utils_begin(uart_seq_item)
            `uvm_field_int(addr,  UVM_ALL_ON)
            `uvm_field_int(wdata, UVM_ALL_ON)
            `uvm_field_int(rdata, UVM_ALL_ON)
            `uvm_field_int(write, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "uart_seq_item");
            super.new(name);
        endfunction
    endclass // uart_seq_item

    typedef uvm_sequencer #(uart_seq_item) uart_sequencer;

    // APB Driver
    class uart_driver extends uvm_driver #(uart_seq_item);
        `uvm_component_utils(uart_driver)

        virtual uart_if.DRIVER vif;

        function new(string name = "uart_driver", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual uart_if.DRIVER)::get(this, "", "vif", vif))
                `uvm_fatal("DRV", "Could not get virtual interface handle!");
        endfunction

        task run_phase(uvm_phase phase);
            // Default Idle State
            vif.PSEL    <= 1'b0;
            vif.PENABLE <= 1'b0;
            vif.PWRITE  <= 1'b0;
            vif.PADDR   <= '0;
            vif.PWDATA  <= '0;

            forever begin
                seq_item_port.get_next_item(req);
                drive_apb_transfer(req);
                seq_item_port.item_done();
            end
        endtask

        task drive_apb_transfer(uart_seq_item item);
            @(posedge vif.PCLK);
            // Setup Phase
            vif.PSEL    <= 1'b1;
            vif.PENABLE <= 1'b0;
            vif.PWRITE  <= item.write;
            vif.PADDR   <= item.addr;
            vif.PWDATA  <= item.wdata;

            @(posedge vif.PCLK);
            // Access Phase
            vif.PENABLE <= 1'b1;

            @(posedge vif.PCLK);
            while (!vif.PREADY) @(posedge vif.PCLK);

            if (!item.write)
                item.rdata = vif.PRDATA;

            // Idle Transition
            vif.PSEL    <= 1'b0;
            vif.PENABLE <= 1'b0;
        endtask
    endclass // uart_driver

    // APB Monitor
    class uart_monitor extends uvm_monitor;
        `uvm_component_utils(uart_monitor)

        virtual uart_if.MONITOR vif;
        uvm_analysis_port #(uart_seq_item) item_collected_port;

        function new(string name = "uart_monitor", uvm_component parent = null);
            super.new(name, parent);
            item_collected_port = new("item_collected_port", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual uart_if.MONITOR)::get(this, "", "vif", vif))
                `uvm_fatal("MON", "Could not get virtual interface handle!");
        endfunction

        task run_phase(uvm_phase phase);
            uart_seq_item item;
            forever begin
                @(posedge vif.PCLK);
                if (vif.PSEL && vif.PENABLE && vif.PREADY) begin
                    item = uart_seq_item::type_id::create("item");
                    item.write = vif.PWRITE;
                    item.addr  = vif.PADDR;
                    item.wdata = vif.PWDATA;
                    item.rdata = vif.PRDATA;

                    if (item.addr[7:0] == UART_STATUS) begin
                        item.rx_error = item.rdata[0];
                        item.rx_valid = item.rdata[1];
                        item.tx_busy  = item.rdata[2];
                    end

                    item_collected_port.write(item);
                end
            end
        endtask
    endclass // uart_monitor

    // Scoreboard (TX Push/Pop Verification)
    class uart_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(uart_scoreboard)

        uvm_analysis_imp #(uart_seq_item, uart_scoreboard) item_imp;

        bit [7:0] expected_tx_q[$];
        bit [7:0] expected_rx_q[$];

        int u_matches    = 0;
        int u_mismatches = 0;

        function new(string name = "uart_scoreboard", uvm_component parent = null);
            super.new(name, parent);
            item_imp = new("item_imp", this);
        endfunction

        function void write(uart_seq_item item);
            if (item.addr[31:16] != 16'h1003)
                return;
            // APB Write to TX Register -> Push to expected TX Queue
            if (item.write && (item.addr[7:0] == UART_TX_DATA)) begin
                expected_tx_q.push_back(item.wdata[7:0]);
                `uvm_info("SCB", $sformatf("Buffered TX Byte: 0x%02h", item.wdata[7:0]), UVM_MEDIUM)
            end

            // APB Read from RX Register -> Validate against RX Queue (if pre-populated)
            if (!item.write && (item.addr[7:0] == UART_RX_DATA)) begin
                if (expected_rx_q.size() > 0) begin
                    bit [7:0] exp_byte = expected_rx_q.pop_front();
                    if (item.rdata[7:0] == exp_byte) begin
                        `uvm_info("SCB", $sformatf("[PASS] RX Byte Match: 0x%02h", item.rdata[7:0]), UVM_LOW)
                        u_matches++;
                    end else begin
                        `uvm_error("SCB", $sformatf("[FAIL] RX Mismatch! Exp: 0x%02h, Got: 0x%02h", exp_byte, item.rdata[7:0]))
                        u_mismatches++;
                    end
                end
            end
        endfunction
    endclass // uart_scoreboard

    // Functional Coverage
    class uart_coverage extends uvm_subscriber #(uart_seq_item);
        `uvm_component_utils(uart_coverage)

        uart_seq_item cov_item;

        covergroup cg_uart_apb;
            option.per_instance = 1;

            cp_addr: coverpoint cov_item.addr[7:0] {
                bins tx_data = {UART_TX_DATA};
                bins rx_data = {UART_RX_DATA};
                bins status  = {UART_STATUS};
                bins ctrl    = {UART_CTRL};
            }

            cp_write: coverpoint cov_item.write {
                bins read_op  = {0};
                bins write_op = {1};
            }

            cp_status: coverpoint {cov_item.tx_busy, cov_item.rx_valid, cov_item.rx_error} {
                bins idle         = {3'b000};
                bins rx_ready     = {3'b010};
                bins tx_active    = {3'b100};
                ignore_bins error = {3'b001};
            }

            cross_op: cross cp_addr, cp_write {
                ignore_bins invalid_reads  = binsof(cp_addr.tx_data) && binsof(cp_write.read_op);
                ignore_bins invalid_writes = (binsof(cp_addr.rx_data) || binsof(cp_addr.status)) && binsof(cp_write.write_op);
            }
        endgroup

        function new(string name = "uart_coverage", uvm_component parent = null);
            super.new(name, parent);
            cg_uart_apb = new();
        endfunction

        function void write(uart_seq_item t);
            cov_item = t;
            cg_uart_apb.sample();
        endfunction
    endclass // uart_coverage

    // Agent
    class uart_agent extends uvm_agent;
        `uvm_component_utils(uart_agent)

        uart_driver    driver;
        uart_monitor   monitor;
        uart_sequencer sequencer;

        function new(string name = "uart_agent", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            monitor = uart_monitor::type_id::create("monitor", this);
            if (get_is_active() == UVM_ACTIVE) begin
                driver    = uart_driver::type_id::create("driver", this);
                sequencer = uart_sequencer::type_id::create("sequencer", this);
            end
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            if (get_is_active() == UVM_ACTIVE) begin
                driver.seq_item_port.connect(sequencer.seq_item_export);
            end
        endfunction
    endclass // uart_agent

    // Sub-Environment
    class uart_environment extends uvm_env;
        `uvm_component_utils(uart_environment)

        uart_agent      agent;
        uart_scoreboard scoreboard;
        uart_coverage   cov;

        function new(string name = "uart_environment", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent      = uart_agent::type_id::create("agent", this);
            scoreboard = uart_scoreboard::type_id::create("scoreboard", this);
            cov        = uart_coverage::type_id::create("coverage", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            agent.monitor.item_collected_port.connect(scoreboard.item_imp);
            agent.monitor.item_collected_port.connect(cov.analysis_export);
        endfunction
    endclass // uart_environment

    // Base Sequences
    class uart_base_sequence extends uvm_sequence #(uart_seq_item);
        `uvm_object_utils(uart_base_sequence)

        function new(string name = "uart_base_sequence");
            super.new(name);
        endfunction

        task write_reg(bit [31:0] addr, bit [31:0] data);
            req = uart_seq_item::type_id::create("req");
            start_item(req);
            req.write = 1'b1;
            req.addr  = addr;
            req.wdata = data;
            finish_item(req);
        endtask

        task read_reg(bit [31:0] addr);
            req = uart_seq_item::type_id::create("req");
            start_item(req);
            req.write = 1'b0;
            req.addr  = addr;
            finish_item(req);
        endtask
    endclass // uart_base_sequence

    class uart_tx_string_seq extends uart_base_sequence;
        `uvm_object_utils(uart_tx_string_seq)

        function new(string name = "uart_tx_string_seq");
            super.new(name);
        endfunction

        task body();
            byte msg[$] = {"U", "V", "M", " ", "U", "A", "R", "T", "\n"};
            foreach (msg[i]) begin
                write_reg(32'h1003_0000 + UART_TX_DATA, msg[i]);
                #10us; // Wait for transmission gap
            end
        endtask
    endclass // uart_tx_string_seq

    class uart_full_coverage_seq extends uart_base_sequence;
        `uvm_object_utils(uart_full_coverage_seq)

        function new(string name = "uart_full_coverage_seq");
            super.new(name);
        endfunction

        task body();
            `uvm_info("FULL_COV_SEQ", "Executing Legal Reg Operations...", UVM_LOW)

            // 1. Write/Read CTRL Register (0x0C) -> Hits CTRL Write & Read
            write_reg(32'h1003_000C, 32'h0000_0001);
            read_reg (32'h1003_000C);

            // 2. Read STATUS Register (0x08) while Idle -> Hits STATUS Read & Idle Bin
            read_reg (32'h1003_0008);

            // 3. Write TX DATA Register (0x00) -> Hits TX_DATA Write
            write_reg(32'h1003_0000, 32'h0000_00A5);

            // 4. Read STATUS immediately -> Hits tx_active Bin
            read_reg (32'h1003_0008);

            // Wait for transmission/loopback complete
            #200us;

            // 5. Read STATUS -> Hits rx_ready Bin
            read_reg (32'h1003_0008);

            // 6. Read RX DATA Register (0x04) -> Hits RX_DATA Read
            read_reg (32'h1003_0004);
            
            `uvm_info("FULL_COV_SEQ", "Sequence complete.", UVM_LOW)
        endtask
    endclass

endpackage
