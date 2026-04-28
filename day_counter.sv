// -----------------------------------------------------------------------------
// day_counter  
//      – counts 1–max_days
// -----------------------------------------------------------------------------
module day_counter (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       carry_in,   // from hour_counter carry_out
    input  logic [4:0] max_days,   // from rollover
    input  logic       we,
    input  logic       inc,
    input  logic       dec,
    output logic [4:0] day,
    output logic       carry_out
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            day       <= 5'd1;
            carry_out <= 1'b0;
        end else begin
            carry_out <= 1'b0;

            if (we) begin
                if (inc)
                    day <= (day >= max_days) ? 5'd1 : day + 1'b1;
                else if (dec)
                    day <= (day <= 5'd1) ? max_days : day - 1'b1;
            end else if (carry_in) begin
                if (day >= max_days) begin
                    day       <= 5'd1;
                    carry_out <= 1'b1;
                end else begin
                    day <= day + 1'b1;
                end
            end
        end
    end
endmodule