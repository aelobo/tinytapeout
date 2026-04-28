// -----------------------------------------------------------------------------
// month_counter  
//      – counts 1–12
// -----------------------------------------------------------------------------
module month_counter (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       carry_in,  // from day_counter carry_out
    input  logic       we,
    input  logic       inc,
    input  logic       dec,
    output logic [3:0] month
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            month <= 4'd1;
        end else begin
            if (we) begin
                if (inc)
                    month <= (month == 4'd12) ? 4'd1 : month + 1'b1;
                else if (dec)
                    month <= (month == 4'd1)  ? 4'd12 : month - 1'b1;
            end else if (carry_in) begin
                month <= (month == 4'd12) ? 4'd1 : month + 1'b1;
            end
        end
    end
endmodule