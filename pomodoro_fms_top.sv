// =============================================================================
// pomodoro_fsm
//
// Active only when pomodoro_active is asserted by main_mode_fsm.
//
// btn_set in pomodoro mode repurposed:
//   btn_up_start  → start / pause the timer
//   btn_dn_reset  → reset session back to IDLE
//
// Configurable work/break durations are loaded via we_work / we_break
// (asserted by setup_field_fsm in a future extension – tied low for now).
// Default durations: WORK=25 min, BREAK=5 min.
//
// The countdown uses tick_1hz from the clock divider.
// At expiry the FSM enters ALARM for ALARM_CYCLES cycles, then auto-advances.
//
// Outputs:
//   pomo_display_val[9:0]  – minutes remaining (for display mux)
//   led_work               – red LED on during WORK
//   led_break              – green LED on during BREAK
//   buzzer_en              – pulses during ALARM state
// =============================================================================


module pomodoro_fsm #(
    parameter int WORK_MIN   = 25,   // default work duration  (minutes)
    parameter int BREAK_MIN  = 5,    // default break duration (minutes)
    parameter int ALARM_CYCLES = 10  // buzzer duration        (seconds)
) (
    input  logic       clk,
    input  logic       rst_n,

    input  logic       pomodoro_active, // gate from main_mode_fsm
    input  logic       tick_1hz,        // 1 Hz tick from clk_divider

    // Button inputs (single-cycle pulses)
    input  logic       btn_up_start,    // start / pause
    input  logic       btn_dn_reset,    // reset

    // Configurable durations (from setup; tie we_* low to use defaults)
    input  logic       we_work,         // load work_cfg
    input  logic       we_break,        // load break_cfg
    input  logic [5:0] work_cfg,        // work minutes (1–63)
    input  logic [5:0] break_cfg,       // break minutes (1–63)

    output logic [11:0] pomo_countdown,   // raw seconds remaining (to display)
    output logic [9:0]  pomo_display_val, // approx minutes remaining (legacy)
    output logic        led_work,
    output logic        led_break,
    output logic        buzzer_en
);
    // State encoding
    typedef enum logic [1:0] {
        IDLE  = 2'b00,
        WORK  = 2'b01,
        BREAK = 2'b10,
        ALARM = 2'b11
    } pomo_state_t;

    pomo_state_t state, next;

    // Duration registers (in minutes, converted to seconds for countdown)
    logic [5:0] work_dur;   // minutes
    logic [5:0] break_dur;  // minutes

    // Countdown: seconds remaining (max 63 min × 60 s = 3780 < 2^12)
    logic [11:0] countdown;
    logic        paused;
    logic        expired;   // countdown hit zero
    logic [3:0]  alarm_cnt; // counts alarm cycles

    // ── Duration registers ───────────────────────────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            work_dur  <= WORK_MIN[5:0];
            break_dur <= BREAK_MIN[5:0];
        end else begin
            if (we_work  && state == IDLE) work_dur  <= work_cfg;
            if (we_break && state == IDLE) break_dur <= break_cfg;
        end
    end

    // ── State register ───────────────────────────────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else        state <= next;
    end

    // ── Next-state logic ─────────────────────────────────────────────────────
    always_comb begin
        next = state;

        if (!pomodoro_active || btn_dn_reset) begin
            next = IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (btn_up_start) next = WORK;
                end

                WORK: begin
                    if (expired) next = ALARM;
                end

                BREAK: begin
                    if (expired) next = ALARM;
                end

                ALARM: begin
                    if (alarm_cnt >= ALARM_CYCLES[3:0]) begin
                        // After work alarm → go to BREAK; after break alarm → IDLE
                        // We track which phase just ended via a registered flag (see below)
                        next = IDLE; // overridden in sequential block with phase flag
                    end
                end

                default: next = IDLE;
            endcase
        end
    end

    // ── Phase flag: remembers whether alarm follows WORK or BREAK ───────────
    logic alarm_was_work;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alarm_was_work <= 1'b0;
        end else begin
            if (state == WORK && next == ALARM)
                alarm_was_work <= 1'b1;
            else if (state == BREAK && next == ALARM)
                alarm_was_work <= 1'b0;
        end
    end

    // ── Countdown and pause logic ────────────────────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            countdown <= 12'd0;
            paused    <= 1'b0;
            expired   <= 1'b0;
            alarm_cnt <= 4'd0;
        end else begin
            expired <= 1'b0; // default

            case (state)
                IDLE: begin
                    paused    <= 1'b0;
                    alarm_cnt <= 4'd0;
                    countdown <= {work_dur, 6'd0}; // preload work duration in seconds
                end

                WORK, BREAK: begin
                    // Load countdown when entering this state
                    if (state != next) begin
                        // Transition into WORK or BREAK: preload
                        if (next == WORK)
                            countdown <= {work_dur,  6'd0};
                        else if (next == BREAK)
                            countdown <= {break_dur, 6'd0};
                    end

                    // Toggle pause on btn_up_start
                    if (btn_up_start) paused <= ~paused;

                    // Count down
                    if (!paused && tick_1hz && countdown > 12'd0)
                        countdown <= countdown - 1'b1;

                    if (!paused && tick_1hz && countdown == 12'd1)
                        expired <= 1'b1;
                end

                ALARM: begin
                    paused <= 1'b0;
                    if (tick_1hz) begin
                        alarm_cnt <= alarm_cnt + 1'b1;
                        // Auto-advance after alarm expires
                        if (alarm_cnt >= ALARM_CYCLES[3:0] - 1) begin
                            alarm_cnt <= 4'd0;
                            countdown <= alarm_was_work ?
                                         {break_dur, 6'd0} :
                                         12'd0;
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

    // ── Output logic ─────────────────────────────────────────────────────────
    // pomo_display_val shows minutes remaining (top 6 bits of countdown)
    assign pomo_countdown    = countdown;
    assign pomo_display_val  = countdown[11:2]; // approx minutes (÷60 via shift)

    always_comb begin
        led_work   = (state == WORK);
        led_break  = (state == BREAK);
        buzzer_en  = (state == ALARM);
    end

endmodule