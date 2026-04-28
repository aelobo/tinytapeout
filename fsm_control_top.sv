// =============================================================================
//
// fsm_control_top
//     |-- main_mode_fsm     – CLOCK / DATE / POMODORO / SETUP_CLK / SETUP_DATE
//     |-- setup_field_fsm   – SEL_MIN / SEL_HOUR / SEL_DAY / SEL_MON
//     |-- pomodoro_fsm      – IDLE / WORK / BREAK / ALARM
//
// 
// =============================================================================


module fsm_control_top #(
    parameter int WORK_MIN    = 25,
    parameter int BREAK_MIN   = 5,
    parameter int ALARM_CYCLES = 10
) (
    input  logic       clk,
    input  logic       rst_n,

    // single cycle button pulse
    input  logic       btn_mode,
    input  logic       btn_set,
    input  logic       btn_up,    // increment in setup; start/pause in pomo
    input  logic       btn_dn,    // decrement in setup; reset in pomo

    // 1 HZ tick from clock divider
    input  logic       tick_1hz,

    // pomodoro
    input  logic       we_work,
    input  logic       we_break,
    input  logic [5:0] work_cfg,
    input  logic [5:0] break_cfg,

    // leap year
    input  logic       leap_year,

    // display control
    output logic [1:0] display_mode,    // 00=CLOCK 01=DATE 10=POMODORO
    output logic [1:0] field_sel,       // which field blinks in setup mode
    output logic       in_setup,

    // clock chain enables
    output logic       we_min,
    output logic       we_hr,
    output logic       we_day,
    output logic       we_mon,

    // pomodoro display
    output logic [11:0] pomo_countdown,
    output logic [9:0]  pomo_display_val,

    // outputs
    output logic       led_work,
    output logic       led_break,
    output logic       buzzer_en
);

    // internal signals
    logic setup_is_date;
    logic pomodoro_active;


    // main mode fsm -----------------------------------------------------------
    main_mode_fsm mode_fsm (
        .clk             (clk),
        .rst_n           (rst_n),
        .btn_mode        (btn_mode),
        .btn_set         (btn_set),
        .display_mode    (display_mode),
        .in_setup        (in_setup),
        .setup_is_date   (setup_is_date),
        .pomodoro_active (pomodoro_active)
    );

    // setup field fsm ---------------------------------------------------------
    setup_field_fsm setup_fsm (
        .clk          (clk),
        .rst_n        (rst_n),
        .in_setup     (in_setup),
        .setup_is_date(setup_is_date),
        .btn_set      (btn_set),
        .btn_up       (btn_up),
        .btn_dn       (btn_dn),
        .field_sel    (field_sel),
        .we_min       (we_min),
        .we_hr        (we_hr),
        .we_day       (we_day),
        .we_mon       (we_mon)
    );

    // pomodoro FSM ------------------------------------------------------------
    pomodoro_fsm #(
        .WORK_MIN    (WORK_MIN),
        .BREAK_MIN   (BREAK_MIN),
        .ALARM_CYCLES(ALARM_CYCLES)
    ) pomo_fsm (
        .clk             (clk),
        .rst_n           (rst_n),
        .pomodoro_active (pomodoro_active),
        .tick_1hz        (tick_1hz),
        .btn_up_start    (btn_up),
        .btn_dn_reset    (btn_dn),
        .we_work         (we_work),
        .we_break        (we_break),
        .work_cfg        (work_cfg),
        .break_cfg       (break_cfg),
        .pomo_countdown  (pomo_countdown),
        .pomo_display_val(pomo_display_val),
        .led_work        (led_work),
        .led_break       (led_break),
        .buzzer_en       (buzzer_en)
    );

endmodule