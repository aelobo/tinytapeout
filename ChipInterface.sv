// =============================================================================
// ChipInterface — Pomodoro Clock
//
// Buttons (active high, PULLMODE=DOWN):
//   btn_left  : enter setup (when outside) / exit setup (when inside)
//   btn_right : cycle mode  (when outside) / cycle field (when inside)
//   btn_up    : increment field in setup / start/pause pomodoro
//   btn_down  : decrement field in setup / reset pomodoro
//
// LED mapping:
//   led[1:0] = display_mode  (00=CLOCK, 01=DATE, 10=POMODORO)
//   led[2]   = in_setup
//   led[3]   = led_work
//   led[4]   = led_break
//   led[5]   = buzzer_en
//   led[7:6] = field_sel
//
// SPI -> MAX7219:
//   spi_clk -> GP18+ (H18)
//   spi_din -> GP20+ (D18)
//   spi_cs  -> GP19+ (F17)
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
    output logic        digit_select,
    output logic        spi_din,
    output logic        spi_cs,
    output logic        spi_clk
);
    assign segment      = 7'b0;
    assign digit_select = 1'b0;

    // -------------------------------------------------------------------------
    // Clock divider: 25MHz -> 12.5MHz for MAX7219
    // -------------------------------------------------------------------------
    reg clk_div;
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) clk_div <= 1'b0;
        else          clk_div <= ~clk_div;
    end

    // -------------------------------------------------------------------------
    // Debounce + single-cycle rising edge pulses
    // -------------------------------------------------------------------------
    localparam int DEBOUNCE_CYCLES = 250_000;

    logic deb_left, deb_right, deb_up, deb_down;
    debounce #(.CYCLES(DEBOUNCE_CYCLES)) db_left  (.clk(clock), .rst_n(reset_n), .in(btn_left),  .out(deb_left));
    debounce #(.CYCLES(DEBOUNCE_CYCLES)) db_right (.clk(clock), .rst_n(reset_n), .in(btn_right), .out(deb_right));
    debounce #(.CYCLES(DEBOUNCE_CYCLES)) db_up    (.clk(clock), .rst_n(reset_n), .in(btn_up),    .out(deb_up));
    debounce #(.CYCLES(DEBOUNCE_CYCLES)) db_down  (.clk(clock), .rst_n(reset_n), .in(btn_down),  .out(deb_down));

    logic pulse_left, pulse_right, pulse_up, pulse_down;
    logic prev_left, prev_right, prev_up, prev_down;

    always_ff @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            prev_left <= 0; prev_right <= 0;
            prev_up   <= 0; prev_down  <= 0;
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
    // 1Hz tick
    // -------------------------------------------------------------------------
    logic tick_1hz;
    clk_divider #(.CLK_FREQ(CLK_FREQ)) tick_gen (
        .clk      (clock),
        .rst_n    (reset_n),
        .tick_1hz (tick_1hz)
    );

    // -------------------------------------------------------------------------
    // Clock chain
    // -------------------------------------------------------------------------
    logic [5:0] sec, min;
    logic [4:0] hour, day;
    logic [3:0] month;
    logic       we_min, we_hr, we_day, we_mon;

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
    // Button routing
    //
    // The FSMs use two signals:
    //   btn_mode -> cycles display modes (CLOCK/DATE/POMODORO)
    //   btn_set  -> enters setup OR exits setup OR cycles fields within setup
    //
    // -------------------------------------------------------------------------
    logic [1:0]  display_mode;
    logic [1:0]  field_sel;
    logic        in_setup;
    logic        in_setup_r;
    logic        setup_is_date;
    logic        pomodoro_active;
    logic [11:0] pomo_countdown;
    logic [9:0]  pomo_display_val;
    logic        led_work, led_break, buzzer_en;

    always_ff @(posedge clock or negedge reset_n) begin
        if (!reset_n) in_setup_r <= 1'b0;
        else          in_setup_r <= in_setup;
    end

    // main_mode_fsm:
    //   btn_right cycles modes only when NOT in setup
    //   btn_left  enters or exits setup
    main_mode_fsm mode_fsm (
        .clk            (clock),
        .rst_n          (reset_n),
        .btn_mode       (pulse_right & ~in_setup_r),
        .btn_set        (pulse_left),
        .display_mode   (display_mode),
        .in_setup       (in_setup),
        .setup_is_date  (setup_is_date),
        .pomodoro_active(pomodoro_active)
    );

    // setup_field_fsm:
    //   btn_right cycles fields only when IN setup
    //   btn_up/down increment/decrement the selected field
    setup_field_fsm field_fsm (
        .clk          (clock),
        .rst_n        (reset_n),
        .in_setup     (in_setup_r),   // use registered version to avoid glitch
        .setup_is_date(setup_is_date),
        .btn_set      (pulse_right & in_setup_r),
        .btn_up       (pulse_up),
        .btn_dn       (pulse_down),
        .field_sel    (field_sel),
        .we_min       (we_min),
        .we_hr        (we_hr),
        .we_day       (we_day),
        .we_mon       (we_mon)
    );

    // pomodoro_fsm:
    //   btn_up starts/pauses, btn_down resets
    pomodoro_fsm #(
        .WORK_MIN    (25),
        .BREAK_MIN   (5),
        .ALARM_CYCLES(10)
    ) pomo_fsm (
        .clk             (clock),
        .rst_n           (reset_n),
        .pomodoro_active (pomodoro_active),
        .tick_1hz        (tick_1hz),
        .btn_up_start    (pulse_up),
        .btn_dn_reset    (pulse_down),
        .we_work         (1'b0),
        .we_break        (1'b0),
        .work_cfg        (6'd25),
        .break_cfg       (6'd5),
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
    // Display — segment patterns
    // -------------------------------------------------------------------------
    localparam [7:0] SEG_0 = 8'h7e;
    localparam [7:0] SEG_1 = 8'h30;
    localparam [7:0] SEG_2 = 8'h6d;
    localparam [7:0] SEG_3 = 8'h79;
    localparam [7:0] SEG_4 = 8'h33;
    localparam [7:0] SEG_5 = 8'h5b;
    localparam [7:0] SEG_6 = 8'h5f;
    localparam [7:0] SEG_7 = 8'h70;
    localparam [7:0] SEG_8 = 8'h7f;
    localparam [7:0] SEG_9 = 8'h7b;
    localparam [7:0] BLANK = 8'h00;

    function automatic [7:0] bcd_to_seg(input [3:0] d);
        case (d)
            4'd0: bcd_to_seg = SEG_0; 4'd1: bcd_to_seg = SEG_1;
            4'd2: bcd_to_seg = SEG_2; 4'd3: bcd_to_seg = SEG_3;
            4'd4: bcd_to_seg = SEG_4; 4'd5: bcd_to_seg = SEG_5;
            4'd6: bcd_to_seg = SEG_6; 4'd7: bcd_to_seg = SEG_7;
            4'd8: bcd_to_seg = SEG_8; 4'd9: bcd_to_seg = SEG_9;
            default: bcd_to_seg = BLANK;
        endcase
    endfunction

    // blink phase
    // toggles at 1Hz for setup cursor
    logic blink_phase;
    always_ff @(posedge clock or negedge reset_n) begin
        if (!reset_n)      blink_phase <= 1'b1;
        else if (tick_1hz) blink_phase <= ~blink_phase;
    end

    // Blank digit when its field is selected in setup and blink_phase is low
    function automatic [7:0] maybe_blank(input [7:0] seg, input [1:0] fld);
        if (in_setup_r && (field_sel == fld) && !blink_phase)
            maybe_blank = BLANK;
        else
            maybe_blank = seg;
    endfunction

    // Lookup-table division
    function automatic [3:0] div10(input [5:0] v);
        if      (v >= 50) div10 = 4'd5;
        else if (v >= 40) div10 = 4'd4;
        else if (v >= 30) div10 = 4'd3;
        else if (v >= 20) div10 = 4'd2;
        else if (v >= 10) div10 = 4'd1;
        else              div10 = 4'd0;
    endfunction

    function automatic [3:0] mod10(input [5:0] v);
        mod10 = v - ({2'b0, div10(v), 1'b0} + {2'b0, div10(v), 3'b0}); // v - div10*10
    endfunction

    function automatic [5:0] div60(input [11:0] v);
        if      (v >= 3540) div60 = 6'd59; else if (v >= 3480) div60 = 6'd58;
        else if (v >= 3420) div60 = 6'd57; else if (v >= 3360) div60 = 6'd56;
        else if (v >= 3300) div60 = 6'd55; else if (v >= 3240) div60 = 6'd54;
        else if (v >= 3180) div60 = 6'd53; else if (v >= 3120) div60 = 6'd52;
        else if (v >= 3060) div60 = 6'd51; else if (v >= 3000) div60 = 6'd50;
        else if (v >= 2940) div60 = 6'd49; else if (v >= 2880) div60 = 6'd48;
        else if (v >= 2820) div60 = 6'd47; else if (v >= 2760) div60 = 6'd46;
        else if (v >= 2700) div60 = 6'd45; else if (v >= 2640) div60 = 6'd44;
        else if (v >= 2580) div60 = 6'd43; else if (v >= 2520) div60 = 6'd42;
        else if (v >= 2460) div60 = 6'd41; else if (v >= 2400) div60 = 6'd40;
        else if (v >= 2340) div60 = 6'd39; else if (v >= 2280) div60 = 6'd38;
        else if (v >= 2220) div60 = 6'd37; else if (v >= 2160) div60 = 6'd36;
        else if (v >= 2100) div60 = 6'd35; else if (v >= 2040) div60 = 6'd34;
        else if (v >= 1980) div60 = 6'd33; else if (v >= 1920) div60 = 6'd32;
        else if (v >= 1860) div60 = 6'd31; else if (v >= 1800) div60 = 6'd30;
        else if (v >= 1740) div60 = 6'd29; else if (v >= 1680) div60 = 6'd28;
        else if (v >= 1620) div60 = 6'd27; else if (v >= 1560) div60 = 6'd26;
        else if (v >= 1500) div60 = 6'd25; else if (v >= 1440) div60 = 6'd24;
        else if (v >= 1380) div60 = 6'd23; else if (v >= 1320) div60 = 6'd22;
        else if (v >= 1260) div60 = 6'd21; else if (v >= 1200) div60 = 6'd20;
        else if (v >= 1140) div60 = 6'd19; else if (v >= 1080) div60 = 6'd18;
        else if (v >= 1020) div60 = 6'd17; else if (v >= 960)  div60 = 6'd16;
        else if (v >= 900)  div60 = 6'd15; else if (v >= 840)  div60 = 6'd14;
        else if (v >= 780)  div60 = 6'd13; else if (v >= 720)  div60 = 6'd12;
        else if (v >= 660)  div60 = 6'd11; else if (v >= 600)  div60 = 6'd10;
        else if (v >= 540)  div60 = 6'd9;  else if (v >= 480)  div60 = 6'd8;
        else if (v >= 420)  div60 = 6'd7;  else if (v >= 360)  div60 = 6'd6;
        else if (v >= 300)  div60 = 6'd5;  else if (v >= 240)  div60 = 6'd4;
        else if (v >= 180)  div60 = 6'd3;  else if (v >= 120)  div60 = 6'd2;
        else if (v >= 60)   div60 = 6'd1;  else                div60 = 6'd0;
    endfunction

    function automatic [5:0] mod60(input [11:0] v);
        // mod60 = v - div60(v)*60 = v - div60(v)*64 + div60(v)*4
        mod60 = v - ({6'b0, div60(v)} << 6) + ({6'b0, div60(v)} << 2);
    endfunction

    // 64-bit segment word: [63:56]=digit1(leftmost) ... [7:0]=digit8
    logic [63:0] segments;
    logic [5:0]  pm, ps; // pomodoro minutes, seconds

    always_comb begin
        pm = div60(pomo_countdown);
        ps = mod60(pomo_countdown);

        case (display_mode)
            2'b00: segments = {                           // CLOCK: HH MM SS --
                maybe_blank(bcd_to_seg(div10(hour)), 2'b01),
                maybe_blank(bcd_to_seg(mod10(hour)), 2'b01),
                maybe_blank(bcd_to_seg(div10(min)),  2'b00),
                maybe_blank(bcd_to_seg(mod10(min)),  2'b00),
                bcd_to_seg(div10(sec)),
                bcd_to_seg(mod10(sec)),
                BLANK, BLANK
            };
            2'b01: segments = {                           // DATE: DD -- MM --
                maybe_blank(bcd_to_seg(div10(day)),   2'b10),
                maybe_blank(bcd_to_seg(mod10(day)),   2'b10),
                BLANK,
                maybe_blank(bcd_to_seg(div10(month)), 2'b11),
                maybe_blank(bcd_to_seg(mod10(month)), 2'b11),
                BLANK, BLANK, BLANK
            };
            2'b10: segments = {                           // POMODORO: -- MM SS --
                BLANK, BLANK,
                bcd_to_seg(div10(pm)),
                bcd_to_seg(mod10(pm)),
                bcd_to_seg(div10(ps)),
                bcd_to_seg(mod10(ps)),
                BLANK, BLANK
            };
            default: segments = {8{BLANK}};
        endcase
    end

    // -------------------------------------------------------------------------
    // MAX7219 driver
    // -------------------------------------------------------------------------
    wire M_max_cs, M_max_dout, M_max_sck, M_max_busy;
    reg [7:0] M_max_addr_in, M_max_din;
    reg       M_max_start;

    max7219 max (
        .clk    (clk_div),
        .rst    (~reset_n),
        .addr_in(M_max_addr_in),
        .din    (M_max_din),
        .start  (M_max_start),
        .cs     (M_max_cs),
        .dout   (M_max_dout),
        .sck    (M_max_sck),
        .busy   (M_max_busy)
    );

    assign spi_cs  = M_max_cs;
    assign spi_din = M_max_dout;
    assign spi_clk = M_max_sck;

    localparam DR_IDLE   = 3'd0;
    localparam DR_RESET  = 3'd1;
    localparam DR_INTENS = 3'd2;
    localparam DR_DECODE = 3'd3;
    localparam DR_SCAN   = 3'd4;
    localparam DR_DIGITS = 3'd5;
    localparam DR_LOOP   = 3'd6;

    reg [2:0] dr_state_q, dr_idx_q;
    reg [7:0] dr_addr, dr_data;

    always @* begin
        dr_addr = 8'h00; dr_data = 8'h00; M_max_start = 1'b0;
        case (dr_state_q)
            DR_RESET:  begin M_max_start=1'b1; dr_addr=8'h0C; dr_data=8'h01; end
            DR_INTENS: begin M_max_start=1'b1; dr_addr=8'h0A; dr_data=8'hFF; end
            DR_DECODE: begin M_max_start=1'b1; dr_addr=8'h09; dr_data=8'h00; end
            DR_SCAN:   begin M_max_start=1'b1; dr_addr=8'h0B; dr_data=8'h07; end
            DR_DIGITS: begin
                M_max_start = 1'b1;
                dr_addr     = {5'b0, dr_idx_q} + 8'h01;
                dr_data     = segments[(dr_idx_q)*8 +: 8];
            end
            default: begin M_max_start=1'b0; dr_addr=8'h00; dr_data=8'h00; end
        endcase
        M_max_addr_in = dr_addr;
        M_max_din     = dr_data;
    end

    wire rst_high = ~reset_n;

    always @(posedge clk_div or posedge rst_high) begin
        if (rst_high) begin
            dr_state_q <= DR_IDLE;
            dr_idx_q   <= 3'h0;
        end else begin
            case (dr_state_q)
                DR_IDLE:   dr_state_q <= DR_RESET;
                DR_RESET:  if (!M_max_busy) dr_state_q <= DR_INTENS;
                DR_INTENS: if (!M_max_busy) dr_state_q <= DR_DECODE;
                DR_DECODE: if (!M_max_busy) dr_state_q <= DR_SCAN;
                DR_SCAN:   if (!M_max_busy) begin dr_state_q <= DR_DIGITS; dr_idx_q <= 3'h0; end
                DR_DIGITS: if (!M_max_busy) begin
                    if (dr_idx_q == 3'd7) begin dr_idx_q <= 3'h0; dr_state_q <= DR_LOOP; end
                    else                         dr_idx_q <= dr_idx_q + 3'h1;
                end
                DR_LOOP: begin dr_state_q <= DR_DIGITS; dr_idx_q <= 3'h0; end
                default: dr_state_q <= DR_IDLE;
            endcase
        end
    end

endmodule


// -----------------------------------------------------------------------------
// debounce
// -----------------------------------------------------------------------------
module debounce #(parameter int CYCLES = 250_000) (
    input  logic clk, rst_n, in,
    output logic out
);
    localparam int W = $clog2(CYCLES);
    logic [W-1:0] count;
    logic state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= '0; state <= 1'b0; out <= 1'b0;
        end else begin
            if (in == state) begin
                count <= '0;
            end else if (count == CYCLES - 1) begin
                state <= in; out <= in; count <= '0;
            end else begin
                count <= count + 1'b1;
            end
        end
    end
endmodule