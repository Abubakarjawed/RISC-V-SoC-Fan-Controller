module apb_slave_fsm (
    input  logic       PCLK,
    input  logic       PRESETn,
    input  logic       PSEL,
    input  logic       PENABLE,
    input  logic       PWRITE,
    input  logic [7:0] PADDR,
    input  logic [7:0] PWDATA,

    // Outputs to APB Bus
    output logic [7:0] PRDATA,
    output logic       PREADY,
    output logic       PSLVERR,

    // ---- SPI-engine side (replaces old test-only rx_data_valid/rx_data_in) ----
    // TX side: engine pulls bytes out of tx_fifo
    input  logic       tx_fifo_rd_en,   // driven by spi_engine (was hardcoded 1'b0)
    output logic [7:0] tx_fifo_rd_data, // to spi_engine.tx_fifo_rd_data
    output logic       tx_fifo_empty,   // to spi_engine.tx_fifo_empty

    // RX side: engine pushes received bytes into rx_fifo
    input  logic       rx_fifo_wr_en,   // from spi_engine
    input  logic [7:0] rx_fifo_wr_data, // from spi_engine
    output logic       rx_fifo_full,    // to spi_engine.rx_fifo_full

    // ---- new: derived control signals for spi_engine ----
    output logic        engine_enable,  // = ctrl_reg_value[0], to spi_engine.enable
    output logic        sclk_tick       // generated from clkdiv_reg_value, to spi_engine.sclk_tick
);
    localparam logic [7:0] CTRL_REG   = 8'h00;
    localparam logic [7:0] STATUS_REG = 8'h04;
    localparam logic [7:0] TX_DATA    = 8'h08;
    localparam logic [7:0] RX_DATA    = 8'h0C;
    localparam logic [7:0] CLKDIV     = 8'h10;

    logic addr_ctrl;
    logic addr_status;
    logic addr_tx;
    logic addr_rx;
    logic addr_clkdiv;

    logic [7:0] ctrl_reg_value;
    logic [7:0] clkdiv_reg_value;

    logic apb_write;
    logic apb_read;
    logic apb_done;

    logic       tx_fifo_wr_en;
    logic [7:0] tx_fifo_wr_data;
    logic       tx_fifo_full;
    // tx_fifo_empty, tx_fifo_rd_en, tx_fifo_rd_data are now ports 

    logic       rx_fifo_rd_en;
    logic       rx_fifo_empty;
    logic [7:0] rx_fifo_rd_data;
    // rx_fifo_full is now a port (declared above)

    typedef enum logic [1:0] {
        IDLE   = 2'b00,
        SETUP  = 2'b01,
        ACCESS = 2'b10
    } apb_state_t;

    apb_state_t current_state, next_state;

    assign addr_ctrl   = (PADDR == CTRL_REG);
    assign addr_status = (PADDR == STATUS_REG);
    assign addr_tx     = (PADDR == TX_DATA);
    assign addr_rx     = (PADDR == RX_DATA);
    assign addr_clkdiv = (PADDR == CLKDIV);

    assign apb_done    = (current_state == ACCESS) && PSEL && PENABLE && PREADY;

    assign apb_write   = apb_done && PWRITE;
    assign apb_read    = apb_done && !PWRITE;

    assign tx_fifo_wr_en   = apb_write && addr_tx;
    assign tx_fifo_wr_data = PWDATA;

    assign rx_fifo_rd_en   = apb_read && addr_rx;
    // tx_fifo_rd_en is now driven by spi_engine externally (top-level port, not assigned here)

    assign PSLVERR = 1'b0;

    // Sequential logic
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // State transition logic
    always_comb begin
        next_state = current_state;
        PREADY = 1'b0;
        
        case (current_state)
            IDLE: begin
                if (PSEL) begin
                    next_state = SETUP;  
                end
            end
            
            SETUP: begin
                next_state = ACCESS;
            end
            
            ACCESS: begin
                if (!PSEL) begin
                    next_state = IDLE;
                end 
                else if (!PENABLE) begin
                    PREADY = 1'b0;
                    next_state = ACCESS;
                end
                else if (tx_fifo_full && PWRITE && addr_tx) begin
                    PREADY = 1'b0;
                end 
                else if (rx_fifo_empty && !PWRITE && addr_rx) begin
                    PREADY = 1'b0;
                end 
                else begin
                    PREADY = 1'b1;
                    next_state = IDLE;
                end
            end

            default: next_state = IDLE;
        endcase
    end

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            ctrl_reg_value   <= 1'b0;
            clkdiv_reg_value <= 1'b0;
        end else begin
            if (apb_write && addr_ctrl) begin
                ctrl_reg_value   <= PWDATA;
            end 
            
            if (apb_write && addr_clkdiv) begin
                clkdiv_reg_value <= PWDATA;
            end
        end
    end

    assign engine_enable = ctrl_reg_value[0];

    // sclk_tick generator: pulses once every (clkdiv_reg_value+1) PCLK cycles.
    // spi_engine toggles SCLK on each tick -> SCLK period = 2*(clkdiv+1) PCLK cycles.
    logic [7:0] div_cnt;
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            div_cnt   <= 8'd0;
            sclk_tick <= 1'b0;
        end else if (engine_enable) begin
            if (div_cnt == clkdiv_reg_value) begin
                div_cnt   <= 8'd0;
                sclk_tick <= 1'b1;
            end else begin
                div_cnt   <= div_cnt + 1'b1;
                sclk_tick <= 1'b0;
            end
        end else begin
            div_cnt   <= 8'd0;
            sclk_tick <= 1'b0;
        end
    end

    always_comb begin 
        PRDATA = 8'h00;

        if (current_state == ACCESS && !PWRITE) begin
            case (PADDR)
                CTRL_REG:   PRDATA = ctrl_reg_value;
                STATUS_REG: PRDATA = {
                    4'b0000, 
                    rx_fifo_empty,    // bit 3    
                    rx_fifo_full,     // bit 2
                    tx_fifo_empty,    // bit 1 
                    tx_fifo_full      // bit 0
                };
                TX_DATA:    PRDATA = 8'h00;
                RX_DATA:    PRDATA = rx_fifo_rd_data;
                CLKDIV:     PRDATA = clkdiv_reg_value;
                default:    PRDATA = 8'h00;
            endcase
        end
    end

    fifo tx_fifo (
    .clk          (PCLK),
    .rst_n        (PRESETn),
    .wr_en        (tx_fifo_wr_en),
    .wr_data      (PWDATA),
    .rd_en        (tx_fifo_rd_en),     // now driven by spi_engine, was hardcoded 1'b0
    .full         (tx_fifo_full),
    .empty        (tx_fifo_empty),
    .rd_data      (tx_fifo_rd_data)
    );

    fifo rx_fifo (
    .clk          (PCLK),
    .rst_n        (PRESETn),
    .wr_en        (rx_fifo_wr_en),     // now driven by spi_engine, was test-only rx_data_valid
    .wr_data      (rx_fifo_wr_data),   // now driven by spi_engine, was test-only rx_data_in
    .rd_en        (rx_fifo_rd_en),
    .full         (rx_fifo_full),
    .empty        (rx_fifo_empty),
    .rd_data      (rx_fifo_rd_data)
    );  

endmodule

module fifo (
    input logic       clk,
    input logic       rst_n,
    input logic       wr_en,
    input logic [7:0] wr_data,
    input logic       rd_en,

    output logic       full,
    output logic       empty,
    output logic [7:0] rd_data
);

    logic [7:0] mem [3:0];
    logic [1:0] write_pointer;
    logic [1:0] read_pointer;
    logic [2:0] count;

    logic do_write;
    logic do_read;

    // FLAGS
    assign empty = (count == 0);
    assign full  = (count == 4);
    
    assign do_write = wr_en && !full;
    assign do_read  = rd_en && !empty;

    assign rd_data = mem[read_pointer];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_pointer <= 2'd0;
            read_pointer  <= 2'd0;
            count         <= 3'd0;
        end else begin
            // WRITE
            if (do_write) begin
                mem[write_pointer] <= wr_data;
                write_pointer <= write_pointer + 1'b1;
            end

            // READ
            if (do_read) begin
                read_pointer <= read_pointer + 1'b1;
            end

            // COUNT
            case ({do_write, do_read})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
            endcase
        end
    end
endmodule
