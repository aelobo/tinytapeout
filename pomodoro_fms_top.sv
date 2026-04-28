// -------------------------------------------------------------------------
// Pomodoro FSM

// -------------------------------------------------------------------------


module pomodoro_fsm #(
    parameter int WORK_MIN    = 25,
    parameter int BREAK_MIN   = 5,
    parameter int ALARM_CYCLES = 10
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       pomodoro_active,
    input  logic       tick_1hz,
    input  logic       btn_up_start,
    input  logic       btn_dn_reset,
    input  logic       we_work,
    input  logic       we_break,
    input  logic [5:0] work_cfg,
    input  logic [5:0] break_cfg,
    output logic [11:0] pomo_countdown,
    output logic [9:0]  pomo_display_val,
    output logic        led_work,
    output logic        led_break,
    output logic        buzzer_en
);
    typedef enum logic [1:0] {
        IDLE  = 2'b00,
        WORK  = 2'b01,
        BREAK = 2'b10,
        ALARM = 2'b11
    } pomo_state_t;

    pomo_state_t state, next;

    logic [5:0] work_dur;
    logic [5:0] break_dur;
    logic [11:0] countdown;
    logic        paused;
    logic        expired;
    logic [3:0]  alarm_cnt;
    logic        alarm_was_work;


    function automatic [11:0] mins_to_secs(input [5:0] m);
        // m*60 = m*64 - m*4 = (m<<6) - (m<<2)
        mins_to_secs = ({6'b0, m} << 6) - ({6'b0, m} << 2);
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            work_dur  <= WORK_MIN[5:0];
            break_dur <= BREAK_MIN[5:0];
        end else begin
            if (we_work  && state == IDLE) work_dur  <= work_cfg;
            if (we_break && state == IDLE) break_dur <= break_cfg;
        end
    end

    // state register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else        state <= next;
    end

    // next-state logic
    always_comb begin
        next = state;
        if (!pomodoro_active || btn_dn_reset) begin
            next = IDLE;
        end else begin
            case (state)
                IDLE:  if (btn_up_start) next = WORK;
                WORK:  if (expired) next = ALARM;
                BREAK: if (expired) next = ALARM;
                ALARM: if (alarm_cnt >= ALARM_CYCLES[3:0]) next = IDLE;
                default: next = IDLE;
            endcase
        end
    end

    // Phase flag
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alarm_was_work <= 1'b0;
        end else begin
            if (state == WORK  && next == ALARM) alarm_was_work <= 1'b1;
            if (state == BREAK && next == ALARM) alarm_was_work <= 1'b0;
        end
    end

    // Countdown logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            countdown <= 12'd0;
            paused    <= 1'b0;
            expired   <= 1'b0;
            alarm_cnt <= 4'd0;
        end else begin
            expired <= 1'b0;

            case (state)
                IDLE: begin
                    paused    <= 1'b0;
                    alarm_cnt <= 4'd0;
                    countdown <= mins_to_secs(work_dur);
                end

                WORK, BREAK: begin
                    if (state != next) begin
                        if (next == WORK)
                            countdown <= mins_to_secs(work_dur);
                        else if (next == BREAK)
                            countdown <= mins_to_secs(break_dur);
                    end
                    if (btn_up_start) paused <= ~paused;
                    if (!paused && tick_1hz && countdown > 12'd0)
                        countdown <= countdown - 1'b1;
                    if (!paused && tick_1hz && countdown == 12'd1)
                        expired <= 1'b1;
                end

                ALARM: begin
                    paused <= 1'b0;
                    if (tick_1hz) begin
                        alarm_cnt <= alarm_cnt + 1'b1;
                        if (alarm_cnt >= ALARM_CYCLES[3:0] - 1) begin
                            alarm_cnt <= 4'd0;
                            countdown <= alarm_was_work ?
                                         mins_to_secs(break_dur) : 12'd0;
                        end
                    end
                end

                default: begin
                    countdown <= 12'd0;
                    paused    <= 1'b0;
                end
            endcase
        end
    end

    assign pomo_countdown   = countdown;
    assign pomo_display_val = countdown[11:2];

    always_comb begin
        led_work  = (state == WORK);
        led_break = (state == BREAK);
        buzzer_en = (state == ALARM);
    end

endmodule