`timescale 1ns/1ps
// pwm_out : DUT output, monitor isse sample karta hai.
// tach_pulse : DUT input, fan model TB se isko drive karta hai
// (simulated fan ka tachometer output).
interface pwm_if (input logic PCLK, input logic PRESETn);
    logic pwm_out;
    logic tach_pulse;
endinterface
