package uart_pkg;

typedef enum logic [1:0] {
    PARITY_NONE = 2'b00, 
    PARITY_ODD  = 2'b01, 
    PARITY_EVEN = 2'b10
} parity_e;

typedef enum logic { 
    STOP_1 = 1'b0, 
    STOP_2 = 1'b1
} stop_e;

typedef enum logic [2:0] {
    IDLE,
    START,
    DATA,
    PARITY,
    STOP,
    STOP2
} state_t;

function automatic logic parity_bit(input logic [7:0] data, input parity_e mode);
    logic p;
    p = ^data; // xor
    unique case (mode)
        PARITY_EVEN: return p;      // total ones (data+parity) even
        PARITY_ODD:  return ~p;     // total ones (data+parity) odd
        default:     return 1'b0;   // PARITY_NONE: unused
    endcase
endfunction

endpackage
