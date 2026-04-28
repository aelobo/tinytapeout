// =============================================================================
// main_mode_fsm
//
// btn_mode cycle through:
//   CLOCK --> DATE --> POMODORO --> CLOCK
//
// From CLOCK or DATE, btn_set enters the corresponding SETUP state:
//   CLOCK  + btn_set --> SETUP_CLK
//   DATE   + btn_set --> SETUP_DATE
//
//
// Outputs:
//   display_mode[1:0]      – 2'b00=CLOCK, 2'b01=DATE, 2'b10=POMODORO
//   in_setup               – high whenever SETUP state is active
//   setup_is_date          – SETUP_CLK vs SETUP_DATE
//   pomodoro_active        – enables pomodoro FSM
// =============================================================================


module main_mode_fsm (
    input  logic       clk,
    input  logic       rst_n,

    input  logic       btn_mode,   // cycle display mode
    input  logic       btn_set,    // enter / exit setup

    output logic [1:0] display_mode,   // 00=CLOCK 01=DATE 10=POMODORO
    output logic       in_setup,       // any SETUP state active
    output logic       setup_is_date,  // 1=SETUP_DATE, 0=SETUP_CLK
    output logic       pomodoro_active // enable pomodoro FSM
);

    typedef enum logic [2:0] {
        CLOCK      = 3'b000,
        DATE       = 3'b001,
        POMODORO   = 3'b010,
        SETUP_CLK  = 3'b011,
        SETUP_DATE = 3'b100
    } mode_state_t;

    mode_state_t state, next;

    // state
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= CLOCK;
        else        state <= next;
    end

    // next state logic
    always_comb begin
        next = state; 

        case (state)
            CLOCK: begin
                if      (btn_mode) next = DATE;
                else if (btn_set)  next = SETUP_CLK;
            end

            DATE: begin
                if      (btn_mode) next = POMODORO;
                else if (btn_set)  next = SETUP_DATE;
            end

            POMODORO: begin
                if (btn_mode) next = CLOCK;
            end

            SETUP_CLK: begin
                if (btn_set) next = CLOCK;  // exit setup
            end

            SETUP_DATE: begin
                if (btn_set) next = DATE;   // exit setup
            end

            default: next = CLOCK;
        endcase
    end

    // output logic
    always_comb begin
        display_mode    = 2'b00;
        in_setup        = 1'b0;
        setup_is_date   = 1'b0;
        pomodoro_active = 1'b0;

        case (state)
            CLOCK:      display_mode = 2'b00;
            DATE:       display_mode = 2'b01;
            POMODORO: begin
                display_mode    = 2'b10;
                pomodoro_active = 1'b1;
            end
            SETUP_CLK: begin
                display_mode  = 2'b00;
                in_setup      = 1'b1;
                setup_is_date = 1'b0;
            end
            SETUP_DATE: begin
                display_mode  = 2'b01;
                in_setup      = 1'b1;
                setup_is_date = 1'b1;
            end
            default: display_mode = 2'b00;
        endcase
    end

endmodule