// =============================================================================
//
// clock_chain_top
//     |-- clk_divider          – sys_clk -> 1 Hz tick
//     |-- sec_counter          – 0–59, carry out
//     |-- min_counter          – 0–59, carry out
//     |-- hour_counter         – 0–23, carry out
//     |-- rollover             – month -> max_days
//     |-- day_counter          – 1–max_days, carry out
//     |-- month_counter        – 1–12
//
// ============================================================================


module clock_chain_top #(
    parameter int CLK_FREQ = 10_000_000
) (
    // global signals
    input  logic       clk,
    input  logic       rst_n,

    // button inputs
    input  logic       btn_up,     // increment in setup mode
    input  logic       btn_dn,     // decrement in setup mode

    // write enables from setup FSM
    input  logic       we_sec,
    input  logic       we_min,
    input  logic       we_hr,
    input  logic       we_day,
    input  logic       we_mon,

    // leap year
    input  logic       leap_year,

    // time outputs
    output logic [5:0] sec,
    output logic [5:0] min,
    output logic [4:0] hour,
    output logic [4:0] day,
    output logic [3:0] month
);

    // internal signals
    logic       tick_1hz;
    logic       carry_sec, carry_min, carry_hr, carry_day;
    logic [4:0] max_days;



    // clock divider
    clk_divider #(.CLK_FREQ(CLK_FREQ)) clk_div (
        .clk      (clk),
        .rst_n    (rst_n),
        .tick_1hz (tick_1hz)
    );

    // seconds
    sec_counter sec_ctn (
        .clk       (clk),
        .rst_n     (rst_n),
        .tick_1hz  (tick_1hz),
        .we        (we_sec),
        .inc       (btn_up),
        .dec       (btn_dn),
        .sec       (sec),
        .carry_out (carry_sec)
    );

    // minutes
    min_counter min_ctn (
        .clk       (clk),
        .rst_n     (rst_n),
        .carry_in  (carry_sec),
        .we        (we_min),
        .inc       (btn_up),
        .dec       (btn_dn),
        .min       (min),
        .carry_out (carry_min)
    );

    // hours
    hour_counter hour_ctn (
        .clk       (clk),
        .rst_n     (rst_n),
        .carry_in  (carry_min),
        .we        (we_hr),
        .inc       (btn_up),
        .dec       (btn_dn),
        .hour      (hour),
        .carry_out (carry_hr)
    );

    // rollover logic
    rollover roll (
        .month     (month),
        .leap_year (leap_year),
        .max_days  (max_days)
    );

    // days
    day_counter day_cnt (
        .clk       (clk),
        .rst_n     (rst_n),
        .carry_in  (carry_hr),
        .max_days  (max_days),
        .we        (we_day),
        .inc       (btn_up),
        .dec       (btn_dn),
        .day       (day),
        .carry_out (carry_day)
    );

    // months
    month_counter month_cnt (
        .clk       (clk),
        .rst_n     (rst_n),
        .carry_in  (carry_day),
        .we        (we_mon),
        .inc       (btn_up),
        .dec       (btn_dn),
        .month     (month)
    );

endmodule