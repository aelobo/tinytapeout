`default_nettype none

/**
 * Decimal_to_MAX.v
 *
 * Enigma Machine
 *
 * ECE 18-500
 * Carnegie Mellon University
 *
 * 
 **/

/*----------------------------------------------------------------------------*
 *  Decimal to MAX                                                            *
 *----------------------------------------------------------------------------*/

module Decimal_to_MAX (
    input       [3:0]   decimal,  
    output reg  [7:0]   seven_seg_display
);

always @* begin
    case (decimal)
        4'h0: seven_seg_display = 8'b0111_1110;
        4'h1: seven_seg_display = 8'b0011_0000;
        4'h2: seven_seg_display = 8'b0110_1101;
        4'h3: seven_seg_display = 8'b0111_1001;
        4'h4: seven_seg_display = 8'b0011_0011;
        4'h5: seven_seg_display = 8'b0101_1011;
        4'h6: seven_seg_display = 8'b0101_1111; 
        4'h7: seven_seg_display = 8'b0111_0000;
        4'h8: seven_seg_display = 8'b0111_1111;
        default: seven_seg_display = 8'b0000_0000;
    endcase
end

endmodule