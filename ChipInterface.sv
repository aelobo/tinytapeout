// =============================================================================
// ChipInterface
//
// btn_right  --> btn_mode  : cycle CLOCK -> DATE -> POMODORO -> CLOCK
// btn_left   --> btn_set   : enter/exit setup mode
// btn_up     --> increment selected field
// btn_down   --> decrement selected field
//
// Buttons are ACTIVE LOW on ULX3S — inverted and debounced here.
//
// LED mapping:
//   led[1:0] = display_mode  (00=CLOCK, 01=DATE, 10=POMODORO)
//   led[2]   = in_setup
//   led[3]   = led_work
//   led[4]   = led_break
//   led[5]   = buzzer_en
//   led[7:6] = field_sel
//
// Seven segment: multiplexed 2-digit display of seconds (tens | ones)
//   digit_select=0 -> ones digit
//   digit_select=1 -> tens digit
// =============================================================================

module ChipInterface #(
    parameter int CLK_FREQ = 25_000_000
) (
    input  logic        clock,
    input  logic        reset_n,
    input  logic        btn_left,
    input  logic        btn_right,
    input  logic        btn_up,
    input  logic        btn_down,
    output logic [7:0]  led,
    output logic [6:0]  segment,
    output logic        digit_select
);

    // -------------------------------------------------------------------------
    // Button debounce + edge detect
    // Buttons are active low: invert first, then debounce, then single-pulse
    // -------------------------------------------------------------------------
    localparam int DEBOUNCE_CYCLES = 250_000; // 10ms at 25MHz

    logic raw_left, raw_right, raw_up, raw_down;
    assign raw_left  = ~btn_left;
    assign raw_right = ~btn_right;
    assign raw_up    = ~btn_up;
    assign raw_down  = ~btn_down;

    logic deb_left, deb_right, deb_up, deb_down;

    debounce #(.CYCLES(DEBOUNCE_CYCLES)) db_left  (.clk(clock), .rst_n(reset_n), .in(raw_left),  .out(deb_left));
    debounce #(.CYCLES(DEBOUNCE_CYCLES)) db_right (.clk(clock), .rst_n(reset_n), .in(raw_right), .out(deb_right));
    debounce #(.CYCLES(DEBOUNCE_CYCLES)) db_up    (.clk(clock), .rst_n(reset_n), .in(raw_up),    .out(deb_up));
    debounce #(.CYCLES(DEBOUNCE_CYCLES)) db_down  (.clk(clock), .rst_n(reset_n), .in(raw_down),  .out(deb_down));

    // single-cycle rising edge pulses
    logic pulse_left, pulse_right, pulse_up, pulse_down;
    logic prev_left, prev_right, prev_up, prev_down;

    always_ff @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            prev_left  <= 1'b0; prev_right <= 1'b0;
            prev_up    <= 1'b0; prev_down  <= 1'b0;
        end else begin
            prev_left  <= deb_left;  prev_right <= deb_right;
            prev_up    <= deb_up;    prev_down  <= deb_down;
        end
    end

    assign pulse_left  = deb_left  & ~prev_left;
    assign pulse_right = deb_right & ~prev_right;
    assign pulse_up    = deb_up    & ~prev_up;
    assign pulse_down  = deb_down  & ~prev_down;

    // -------------------------------------------------------------------------
    // Internal signals
    // -------------------------------------------------------------------------
    logic [5:0] sec, min;
    logic [4:0] hour, day;
    logic [3:0] month;

    logic [1:0] display_mode;
    logic [1:0] field_sel;
    logic        in_setup;
    logic        we_min, we_hr, we_day, we_mon;
    logic [11:0] pomo_countdown;
    logic [9:0]  pomo_display_val;
    logic        led_work, led_break, buzzer_en;
    logic        tick_1hz;

    clk_divider #(.CLK_FREQ(CLK_FREQ)) tick_gen (
        .clk      (clock),
        .rst_n    (reset_n),
        .tick_1hz (tick_1hz)
    );

    // -------------------------------------------------------------------------
    // clock_chain_top
    // -------------------------------------------------------------------------
    clock_chain_top #(.CLK_FREQ(CLK_FREQ)) clk_chain (
        .clk       (clock),
        .rst_n     (reset_n),
        .btn_up    (pulse_up),
        .btn_dn    (pulse_down),
        .we_sec    (1'b0),
        .we_min    (we_min),
        .we_hr     (we_hr),
        .we_day    (we_day),
        .we_mon    (we_mon),
        .leap_year (1'b0),
        .sec       (sec),
        .min       (min),
        .hour      (hour),
        .day       (day),
        .month     (month)
    );

    // -------------------------------------------------------------------------
    // fsm_control_top
    // -------------------------------------------------------------------------
    fsm_control_top #(
        .WORK_MIN    (25),
        .BREAK_MIN   (5),
        .ALARM_CYCLES(10)
    ) fsm_ctrl (
        .clk             (clock),
        .rst_n           (reset_n),
        .btn_mode        (pulse_right),
        .btn_set         (pulse_left),
        .btn_up          (pulse_up),
        .btn_dn          (pulse_down),
        .tick_1hz        (tick_1hz),
        .we_work         (1'b0),
        .we_break        (1'b0),
        .work_cfg        (6'd25),
        .break_cfg       (6'd5),
        .leap_year       (1'b0),
        .display_mode    (display_mode),
        .field_sel       (field_sel),
        .in_setup        (in_setup),
        .we_min          (we_min),
        .we_hr           (we_hr),
        .we_day          (we_day),
        .we_mon          (we_mon),
        .pomo_countdown  (pomo_countdown),
        .pomo_display_val(pomo_display_val),
        .led_work        (led_work),
        .led_break       (led_break),
        .buzzer_en       (buzzer_en)
    );

    // -------------------------------------------------------------------------
    // LEDs
    // -------------------------------------------------------------------------
    assign led[1:0] = display_mode;
    assign led[2]   = in_setup;
    assign led[3]   = led_work;
    assign led[4]   = led_break;
    assign led[5]   = buzzer_en;
    assign led[7:6] = field_sel;

    // -------------------------------------------------------------------------
    // 2-digit multiplexed seven segment display
    // digit_select=0 -> ones,  digit_select=1 -> tens
    // Refresh at ~500 Hz (switch every 25_000 cycles at 25 MHz)
    // -------------------------------------------------------------------------
    localparam int MUX_CYCLES = CLK_FREQ / 500;
    localparam int MUX_W      = $clog2(MUX_CYCLES);

    logic [MUX_W-1:0] mux_count;
    logic             mux_sel;

    always_ff @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            mux_count <= '0;
            mux_sel   <= 1'b0;
        end else begin
            if (mux_count == MUX_CYCLES - 1) begin
                mux_count <= '0;
                mux_sel   <= ~mux_sel;
            end else begin
                mux_count <= mux_count + 1'b1;
            end
        end
    end

    logic [3:0] sec_ones, sec_tens;
    assign sec_ones = sec % 10;
    assign sec_tens = sec / 10;

    assign digit_select = mux_sel;

    BCDtoSevenSegment seg_disp (
        .bcd    (mux_sel ? sec_tens : sec_ones),
        .segment(segment)
    );

endmodule


// -----------------------------------------------------------------------------
// debounce: input must be stable for CYCLES consecutive cycles
// -----------------------------------------------------------------------------
module debounce #(
    parameter int CYCLES = 250_000
) (
    input  logic clk,
    input  logic rst_n,
    input  logic in,
    output logic out
);
    localparam int W = $clog2(CYCLES);
    logic [W-1:0] count;
    logic         state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= '0;
            state <= 1'b0;
            out   <= 1'b0;
        end else begin
            if (in == state) begin
                count <= '0;
            end else begin
                if (count == CYCLES - 1) begin
                    state <= in;
                    out   <= in;
                    count <= '0;
                end else begin
                    count <= count + 1'b1;
                end
            end
        end
    end
endmodule


// -----------------------------------------------------------------------------
// BCDtoSevenSegment
// -----------------------------------------------------------------------------
module BCDtoSevenSegment (
    input  logic [3:0] bcd,
    output logic [6:0] segment
);
    always_comb
        unique case (bcd)
            4'd0:  segment = 7'b011_1111;
            4'd1:  segment = 7'b000_0110;
            4'd2:  segment = 7'b101_1011;
            4'd3:  segment = 7'b100_1111;
            4'd4:  segment = 7'b110_0110;
            4'd5:  segment = 7'b110_1101;
            4'd6:  segment = 7'b111_1101;
            4'd7:  segment = 7'b000_0111;
            4'd8:  segment = 7'b111_1111;
            4'd9:  segment = 7'b110_0111;
            4'd10: segment = 7'b111_0111;
            4'd11: segment = 7'b111_1100;
            4'd12: segment = 7'b011_1001;
            4'd13: segment = 7'b101_1110;
            4'd14: segment = 7'b111_1001;
            4'd15: segment = 7'b111_0001;
        endcase
endmodule : BCDtoSevenSegment