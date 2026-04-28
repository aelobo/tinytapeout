// -----------------------------------------------------------------------------
// clk_divider
//      - divides sys_clk by CLK_FREQ to produce single-cycle 1 Hz tick
//      - PARAMETER: CLK_FREQ – system clock frequency in Hz (default 10 MHz)
// -----------------------------------------------------------------------------
module clk_divider #(
    parameter int CLK_FREQ = 10_000_000
) (
    input  logic clk,
    input  logic rst_n,
    output logic tick_1hz
);
    localparam int COUNT_MAX = CLK_FREQ - 1;        // max count before tick
    localparam int CNT_W = $clog2(COUNT_MAX + 1);   // count width

    logic [CNT_W-1:0] count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count    <= '0;
            tick_1hz <= 1'b0;
        end else begin
            if (count == COUNT_MAX) begin
                count    <= '0;
                tick_1hz <= 1'b1;
            end else begin
                count    <= count + 1'b1;
                tick_1hz <= 1'b0;
            end
        end
    end
endmodule