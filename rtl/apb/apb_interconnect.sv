module apb_interconnect #(
    parameter logic [31:0] SPI_BASE_ADDR  = 32'h1000_0000,
    parameter logic [31:0] PWM_BASE_ADDR  = 32'h1001_0000,
    parameter logic [31:0] SRAM_BASE_ADDR = 32'h1002_0000,
    parameter logic [31:0] UART_BASE_ADDR = 32'h1003_0000,
    parameter logic [31:0] ADDR_MASK      = 32'hFFFF_0000
)   (

    // Master Interface (from CPU)
    input  logic [31:0] m_paddr,
    input  logic        m_psel,
    input  logic        m_penable,
    input  logic        m_pwrite,
    input  logic [31:0] m_pwdata,
    output logic [31:0] m_prdata,
    output logic        m_pready,
    output logic        m_pslverr,

    // Slave 0 (SPI)
    output logic [31:0] s0_paddr,
    output logic        s0_psel,
    output logic        s0_penable,
    output logic        s0_pwrite,
    output logic [31:0] s0_pwdata,
    input  logic [31:0] s0_prdata,
    input  logic        s0_pready,
    input  logic        s0_pslverr,

    // Slave 1 (PWM)
    output logic [31:0] s1_paddr,
    output logic        s1_psel,
    output logic        s1_penable,
    output logic        s1_pwrite,
    output logic [31:0] s1_pwdata,
    input  logic [31:0] s1_prdata,
    input  logic        s1_pready,
    input  logic        s1_pslverr,

    // Slave 2 (Config SRAM)    
    output logic [31:0] s2_paddr,
    output logic        s2_psel,
    output logic        s2_penable,
    output logic        s2_pwrite,
    output logic [31:0] s2_pwdata,
    input  logic [31:0] s2_prdata,
    input  logic        s2_pready,
    input  logic        s2_pslverr,

    // Slave 3 (UART)
    output logic [31:0] s3_paddr,
    output logic        s3_psel,
    output logic        s3_penable,
    output logic        s3_pwrite,
    output logic [31:0] s3_pwdata,
    input  logic [31:0] s3_prdata,
    input  logic        s3_pready,
    input  logic        s3_pslverr
);

    // Rule 1: Downstream Forwarding
    assign s0_paddr   = m_paddr;
    assign s0_pwdata  = m_pwdata;
    assign s0_pwrite  = m_pwrite;
    assign s0_penable = m_penable;
    
    assign s1_paddr   = m_paddr;
    assign s1_pwdata  = m_pwdata;
    assign s1_pwrite  = m_pwrite;
    assign s1_penable = m_penable;
    
    assign s2_paddr   = m_paddr;
    assign s2_pwdata  = m_pwdata;
    assign s2_pwrite  = m_pwrite;
    assign s2_penable = m_penable;
    
    assign s3_paddr   = m_paddr;
    assign s3_pwdata  = m_pwdata;
    assign s3_pwrite  = m_pwrite;
    assign s3_penable = m_penable;

    // Rule 2: Address Decoding
    always_comb begin 
        s0_psel = 1'b0;
        s1_psel = 1'b0;
        s2_psel = 1'b0;
        s3_psel = 1'b0;

        if (m_psel) begin
            case (m_paddr & ADDR_MASK)
                (SPI_BASE_ADDR  & ADDR_MASK): s0_psel = 1'b1;
                (PWM_BASE_ADDR  & ADDR_MASK): s1_psel = 1'b1;
                (SRAM_BASE_ADDR & ADDR_MASK): s2_psel = 1'b1;
                (UART_BASE_ADDR & ADDR_MASK): s3_psel = 1'b1;
                default: ;
            endcase
        end
    end

    // Rule 3: Upstream Multiplexing
    always_comb begin
        if (s0_psel) begin
            m_prdata  = s0_prdata;
            m_pready  = s0_pready;
            m_pslverr = s0_pslverr;
        end else if (s1_psel) begin
            m_prdata  = s1_prdata;
            m_pready  = s1_pready;
            m_pslverr = s1_pslverr;
        end else if (s2_psel) begin
            m_prdata  = s2_prdata;
            m_pready  = s2_pready;
            m_pslverr = s2_pslverr;
        end else if (s3_psel) begin
            m_prdata  = s3_prdata;
            m_pready  = s3_pready;
            m_pslverr = s3_pslverr;
        end else begin // Decode error / unmapped address
            m_prdata  = 32'h0;
            m_pready  = 1'b1;                    // Terminate transfer so CPU does not hang
            m_pslverr = m_psel && m_penable;     // Report bus error to CPU
        end
    end

endmodule
