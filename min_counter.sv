// -----------------------------------------------------------------------------
// min_counter
//      - counts minutes 0–59  
// -----------------------------------------------------------------------------
module min_counter (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       carry_in,  // from sec_counter carry_out
    input  logic       we,
    input  logic       inc,
    input  logic       dec,
    output logic [5:0] min,
    output logic       carry_out
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            min       <= 6'd0;
            carry_out <= 1'b0;
        end else begin
            carry_out <= 1'b0;

            if (we) begin
                // manual wrap around logic
                if (inc)
                    min <= (min == 6'd59) ? 6'd0 : min + 1'b1;
                else if (dec)
                    min <= (min == 6'd0)  ? 6'd59 : min - 1'b1;
            end else if (carry_in) begin
                if (min == 6'd59) begin
                    min       <= 6'd0;
                    carry_out <= 1'b1;
                end else begin
                    min <= min + 1'b1;
                end
            end
        end
    end
endmodule