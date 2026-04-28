// -----------------------------------------------------------------------------
// rollover
//      - combinational max day count for month
//      - leap year (optional) tie to 0 for default 28 days
// -----------------------------------------------------------------------------
module rollover (
    input  logic [3:0] month,      // 1–12
    input  logic       leap_year,  // 1 = current year is a leap year
    output logic [4:0] max_days    // 28–31
);
    always_comb begin
        case (month)
            4'd1:        max_days = 5'd31;  // january
            4'd2:        max_days = leap_year ? 5'd29 : 5'd28;  // february
            4'd3:        max_days = 5'd31;  // march
            4'd4:        max_days = 5'd30;  // april
            4'd5:        max_days = 5'd31;  // may
            4'd6:        max_days = 5'd30;  // june
            4'd7:        max_days = 5'd31;  // july
            4'd8:        max_days = 5'd31;  // august
            4'd9:        max_days = 5'd30;  // september
            4'd10:       max_days = 5'd31;  // october
            4'd11:       max_days = 5'd30;  // november
            4'd12:       max_days = 5'd31;  // december
            default:     max_days = 5'd31;
        endcase
    end
endmodule