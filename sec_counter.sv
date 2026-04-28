// -----------------------------------------------------------------------------
// sec_counter
//      * counts seconds 0–59
//      - increments on tick_1hz
//      - SET mode: use btn_up/btn_dn (field_sel must be asserted by the FSM)
//      - carry_out asserted for one cycle when rolling from 59 to 0
// -----------------------------------------------------------------------------
module sec_counter (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       tick_1hz,  // 1 Hz tick
    input  logic       we,        // write enable from setup FSM
    input  logic       inc,       // increment selected field
    input  logic       dec,       // decrement selected field
    output logic [5:0] sec,       // 0–59
    output logic       carry_out  // asserted when 59 -> 0
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sec       <= 6'd0;
            carry_out <= 1'b0;
        end else begin
            carry_out <= 1'b0;  // default

            if (we) begin
                // manual wrap around logic
                if (inc)
                    sec <= (sec == 6'd59) ? 6'd0 : sec + 1'b1;
                else if (dec)
                    sec <= (sec == 6'd0)  ? 6'd59 : sec - 1'b1;
            end else if (tick_1hz) begin
                if (sec == 6'd59) begin
                    sec       <= 6'd0;
                    carry_out <= 1'b1;
                end else begin
                    sec <= sec + 1'b1;
                end
            end
        end
    end
endmodule