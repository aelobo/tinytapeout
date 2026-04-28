// -----------------------------------------------------------------------------
// hour_coutner
//      - counts hours 0–23  
// -----------------------------------------------------------------------------
module hour_counter (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       carry_in,  // from min_counter carry_out
    input  logic       we,
    input  logic       inc,
    input  logic       dec,
    output logic [4:0] hour,
    output logic       carry_out
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hour      <= 5'd0;
            carry_out <= 1'b0;
        end else begin
            carry_out <= 1'b0;

            if (we) begin
                // manual wrap around logic
                if (inc)
                    hour <= (hour == 5'd23) ? 5'd0 : hour + 1'b1;
                else if (dec)
                    hour <= (hour == 5'd0)  ? 5'd23 : hour - 1'b1;
            end else if (carry_in) begin
                if (hour == 5'd23) begin
                    hour      <= 5'd0;
                    carry_out <= 1'b1;
                end else begin
                    hour <= hour + 1'b1;
                end
            end
        end
    end
endmodule