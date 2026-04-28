// =============================================================================
// spi_display.sv
// SPI display pipeline for TinyTapeout Pomodoro Clock
//
// Modelled directly on top.v reference design (16 MHz TinyFPGA BX).
//
// Hierarchy:
//   spi_display_top
//     ├── display_mux          – selects time / date / pomodoro data
//     ├── digit_to_seg  (×8)   – BCD nibble → MAX7219 segment byte
//     │     └── Decimal_to_MAX (existing)
//     ├── display_driver       – init + continuous refresh FSM
//     │     └── max7219        (existing)
//     │           └── spi_master (existing)
//     │                 └── counter (required by max7219)
//     └── led_buzzer_driver    – registered LED / buzzer pad outputs
//
// Reset polarity: rst_n (active-low) throughout this file.
// max7219 / spi_master use active-high rst; polarity is adapted inline.
// =============================================================================



// -----------------------------------------------------------------------------
// display_mux
//   Produces an 8-digit segment array (64 bits packed, digit 0 at [63:56])
//   matching the packing convention in top.v:
//     segments[63:56] = digit shown at position 1 (leftmost)
//     segments[ 7: 0] = digit shown at position 8 (rightmost)
//
//   display_mode:
//     2'b00 = CLOCK      →  HH MM SS -- (positions 1-6)
//     2'b01 = DATE       →  DD MM ---- (positions 1-4)
//     2'b10 = POMODORO   →  -- MM SS -- (positions 3-6)
//
//   Digits are passed as 4-bit BCD (0–9) or 4'hF (BLANK).
//   digit_to_seg converts them to segment bytes; BLANK → 8'h00.
//
//   During setup mode the active field pair blinks at 1 Hz via blink_phase.
// -----------------------------------------------------------------------------
module display_mux (
    input  logic [1:0]  display_mode,

    // Clock chain inputs (binary)
    input  logic [5:0]  sec,
    input  logic [5:0]  min,
    input  logic [4:0]  hour,
    input  logic [4:0]  day,
    input  logic [3:0]  month,

    // Pomodoro countdown (raw seconds remaining)
    input  logic [11:0] pomo_countdown,

    // Setup blink
    input  logic        in_setup,
    input  logic [1:0]  field_sel,   // 00=MIN 01=HOUR 10=DAY 11=MON
    input  logic        blink_phase, // 1 Hz toggle

    // 8 BCD digit outputs [7]=leftmost [0]=rightmost
    output logic [3:0]  digit [7:0]
);
    localparam BLANK = 4'hF;

    // Decompose binary fields to BCD tens/units
    logic [3:0] sec_t,  sec_u;
    logic [3:0] min_t,  min_u;
    logic [3:0] hr_t,   hr_u;
    logic [3:0] day_t,  day_u;
    logic [3:0] mon_t,  mon_u;
    logic [3:0] pm_t,   pm_u;
    logic [3:0] ps_t,   ps_u;
    logic [6:0] pomo_min;
    logic [5:0] pomo_sec_rem;

    always_comb begin
        sec_t = 4'(sec  / 10);   sec_u = 4'(sec  % 10);
        min_t = 4'(min  / 10);   min_u = 4'(min  % 10);
        hr_t  = 4'(hour / 10);   hr_u  = 4'(hour % 10);
        day_t = 4'(day  / 10);   day_u = 4'(day  % 10);
        mon_t = 4'(month / 10);  mon_u = 4'(month % 10);

        pomo_min     = 7'(pomo_countdown / 60);
        pomo_sec_rem = 6'(pomo_countdown % 60);
        pm_t = 4'(pomo_min     / 10);  pm_u = 4'(pomo_min     % 10);
        ps_t = 4'(pomo_sec_rem / 10);  ps_u = 4'(pomo_sec_rem % 10);
    end

    // Blink helper: returns BLANK when the field is selected and phase is low
    function automatic logic [3:0] maybe_blank(
        input logic [3:0] val,
        input logic [1:0] this_field
    );
        if (in_setup && (field_sel == this_field) && !blink_phase)
            return BLANK;
        else
            return val;
    endfunction

    always_comb begin
        for (int i = 0; i < 8; i++) digit[i] = BLANK;

        case (display_mode)
            // ── CLOCK  pos: [H H M M S S -- --] ──────────────────────────
            2'b00: begin
                digit[7] = maybe_blank(hr_t,  2'b01);
                digit[6] = maybe_blank(hr_u,  2'b01);
                digit[5] = maybe_blank(min_t, 2'b00);
                digit[4] = maybe_blank(min_u, 2'b00);
                digit[3] = sec_t;
                digit[2] = sec_u;
                digit[1] = BLANK;
                digit[0] = BLANK;
            end

            // ── DATE  pos: [D D -- M M -- -- --] ─────────────────────────
            2'b01: begin
                digit[7] = maybe_blank(day_t, 2'b10);
                digit[6] = maybe_blank(day_u, 2'b10);
                digit[5] = BLANK;
                digit[4] = maybe_blank(mon_t, 2'b11);
                digit[3] = maybe_blank(mon_u, 2'b11);
                digit[2] = BLANK;
                digit[1] = BLANK;
                digit[0] = BLANK;
            end

            // ── POMODORO  pos: [-- -- M M S S -- --] ─────────────────────
            2'b10: begin
                digit[7] = BLANK;
                digit[6] = BLANK;
                digit[5] = pm_t;
                digit[4] = pm_u;
                digit[3] = ps_t;
                digit[2] = ps_u;
                digit[1] = BLANK;
                digit[0] = BLANK;
            end

            default: begin
                for (int i = 0; i < 8; i++) digit[i] = BLANK;
            end
        endcase
    end
endmodule


// -----------------------------------------------------------------------------
// digit_to_seg
//   Wraps Decimal_to_MAX. BLANK (4'hF) → 8'h00.
// -----------------------------------------------------------------------------
module digit_to_seg (
    input  logic [3:0] bcd,
    output logic [7:0] seg_pattern
);
    wire [7:0] dec_out;
    Decimal_to_MAX dtm (
        .decimal          (bcd),
        .seven_seg_display(dec_out)
    );
    // Decimal_to_MAX default case already returns 8'h00 for out-of-range,
    // but be explicit for the BLANK sentinel 4'hF.
    assign seg_pattern = (bcd == 4'hF) ? 8'h00 : dec_out;
endmodule


// -----------------------------------------------------------------------------
// display_driver
//   Init + continuous refresh FSM, directly ported from top.v's FSM pattern.
//
//   Sequence (mirrors top.v exactly):
//     IDLE          → deassert rst, go to SEND_RESET
//     SEND_RESET    → send 0x0C/0x01 (shutdown off),  wait busy==0
//     SEND_INTENSITY→ send 0x0A/0x0F (intensity mid), wait busy==0
//     SEND_NO_DECODE→ send 0x09/0x00 (raw segments),  wait busy==0
//     SEND_ALL_DIGITS→send 0x0B/0x07 (scan all 8),    wait busy==0
//     SEND_DIGITS   → walk index 0-7: addr = index+1, data = segments byte
//                     when all 8 sent, loop back to SEND_DIGITS
//
//   segments[63:56] → addr 0x01 (digit 1, leftmost)
//   segments[ 7: 0] → addr 0x08 (digit 8, rightmost)
//   Matches top.v: max_addr = M_segment_index_q + 1
//                  max_data = M_segments_q[(index)*8+7-:8]
// -----------------------------------------------------------------------------
module display_driver (
    input  logic        clk,
    input  logic        rst_n,

    // Packed segment data: [63:56]=leftmost digit, [7:0]=rightmost
    input  logic [63:0] segments,

    // Outputs to max7219 instance
    output logic [7:0]  max_addr,
    output logic [7:0]  max_data,
    output logic        max_start,
    output logic        max_rst,    // active-high for max7219
    input  logic        max_busy
);
    localparam IDLE_S         = 3'd0;
    localparam SEND_RESET_S   = 3'd1;
    localparam SEND_INTENS_S  = 3'd2;
    localparam SEND_NODECODE_S= 3'd3;
    localparam SEND_SCANALL_S = 3'd4;
    localparam SEND_DIGITS_S  = 3'd5;

    reg [2:0] state_q, state_d;
    reg [2:0] seg_idx_q, seg_idx_d;  // 0–7
    reg       rst_reg;               // local active-high rst for max7219

    assign max_rst = rst_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q   <= IDLE_S;
            seg_idx_q <= 3'd0;
            rst_reg   <= 1'b1;   // hold max7219 in reset until we're ready
        end else begin
            state_q   <= state_d;
            seg_idx_q <= seg_idx_d;
            rst_reg   <= (state_q == IDLE_S) ? 1'b1 : 1'b0;
        end
    end

    always_comb begin
        // Defaults – hold state
        state_d   = state_q;
        seg_idx_d = seg_idx_q;
        max_addr  = 8'h00;
        max_data  = 8'h00;
        max_start = 1'b0;

        case (state_q)
            // ── Release reset, begin init sequence ────────────────────────
            IDLE_S: begin
                seg_idx_d = 3'd0;
                state_d   = SEND_RESET_S;
            end

            // ── Shutdown register: normal operation ───────────────────────
            SEND_RESET_S: begin
                max_start = 1'b1;
                max_addr  = 8'h0C;
                max_data  = 8'h01;
                if (!max_busy)
                    state_d = SEND_INTENS_S;
            end

            // ── Intensity: mid brightness (8/32) ─────────────────────────
            SEND_INTENS_S: begin
                max_start = 1'b1;
                max_addr  = 8'h0A;
                max_data  = 8'h08;
                if (!max_busy)
                    state_d = SEND_NODECODE_S;
            end

            // ── Decode mode: no decode (raw segment bytes) ────────────────
            SEND_NODECODE_S: begin
                max_start = 1'b1;
                max_addr  = 8'h09;
                max_data  = 8'h00;
                if (!max_busy)
                    state_d = SEND_SCANALL_S;
            end

            // ── Scan limit: display all 8 digits ─────────────────────────
            SEND_SCANALL_S: begin
                max_start = 1'b1;
                max_addr  = 8'h0B;
                max_data  = 8'h07;
                if (!max_busy)
                    state_d = SEND_DIGITS_S;
            end

            // ── Continuous refresh: digits 0-7, then loop ─────────────────
            // Packing matches top.v:
            //   addr = seg_idx + 1  (1=leftmost, 8=rightmost on MAX7219)
            //   data = segments[(seg_idx * 8) + 7 -: 8]
            //        = segments[63:56] for idx=0, segments[7:0] for idx=7
            SEND_DIGITS_S: begin
                if (seg_idx_q < 3'd7 || seg_idx_q == 3'd7) begin
                    max_start = 1'b1;
                    max_addr  = {5'b0, seg_idx_q} + 8'h01;
                    max_data  = segments[(seg_idx_q * 8) +: 8];
                    if (!max_busy) begin
                        if (seg_idx_q == 3'd7)
                            seg_idx_d = 3'd0;      // loop back
                        else
                            seg_idx_d = seg_idx_q + 3'd1;
                    end
                end
            end

            default: state_d = IDLE_S;
        endcase
    end
endmodule


// -----------------------------------------------------------------------------
// led_buzzer_driver
//   One register deep to avoid glitches from combinational FSM outputs.
// -----------------------------------------------------------------------------
module led_buzzer_driver (
    input  logic clk,
    input  logic rst_n,
    input  logic led_work_in,
    input  logic led_break_in,
    input  logic buzzer_en_in,
    output logic led_work,
    output logic led_break,
    output logic buzzer
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            led_work  <= 1'b0;
            led_break <= 1'b0;
            buzzer    <= 1'b0;
        end else begin
            led_work  <= led_work_in;
            led_break <= led_break_in;
            buzzer    <= buzzer_en_in;
        end
    end
endmodule


// =============================================================================
// spi_display_top
// =============================================================================
module spi_display_top (
    input  logic        clk,
    input  logic        rst_n,

    // Clock chain
    input  logic [5:0]  sec,
    input  logic [5:0]  min,
    input  logic [4:0]  hour,
    input  logic [4:0]  day,
    input  logic [3:0]  month,

    // FSM control
    input  logic [1:0]  display_mode,
    input  logic        in_setup,
    input  logic [1:0]  field_sel,

    // Pomodoro FSM
    input  logic [11:0] pomo_countdown,
    input  logic        led_work_in,
    input  logic        led_break_in,
    input  logic        buzzer_en_in,

    // Timing
    input  logic        tick_1hz,

    // SPI outputs → MAX7219
    output logic        spi_clk,   // out0
    output logic        spi_din,   // out1
    output logic        spi_cs,    // out2

    // LED / buzzer outputs
    output logic        led_work,  // out3
    output logic        led_break, // out4
    output logic        buzzer     // out5
);

    // ── Blink phase (1 Hz toggle for setup cursor) ───────────────────────────
    logic blink_phase;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)        blink_phase <= 1'b1;
        else if (tick_1hz) blink_phase <= ~blink_phase;
    end

    // ── Display mux → 8 BCD digits ──────────────────────────────────────────
    logic [3:0] bcd_digit [7:0];

    display_mux u_mux (
        .display_mode   (display_mode),
        .sec            (sec),
        .min            (min),
        .hour           (hour),
        .day            (day),
        .month          (month),
        .pomo_countdown (pomo_countdown),
        .in_setup       (in_setup),
        .field_sel      (field_sel),
        .blink_phase    (blink_phase),
        .digit          (bcd_digit)
    );

    // ── digit_to_seg × 8 → segment bytes ────────────────────────────────────
    logic [7:0] seg_byte [7:0];

    generate
        genvar gi;
        for (gi = 0; gi < 8; gi++) begin : gen_seg
            digit_to_seg u_dts (
                .bcd         (bcd_digit[gi]),
                .seg_pattern (seg_byte[gi])
            );
        end
    endgenerate

    // ── Pack segment bytes into 64-bit word (matches top.v convention) ───────
    // seg_byte[7]=leftmost → segments[63:56], seg_byte[0]=rightmost → [7:0]
    logic [63:0] segments;
    always_comb begin
        for (int k = 0; k < 8; k++)
            segments[(k * 8) +: 8] = seg_byte[k];
    end

    // ── display_driver ───────────────────────────────────────────────────────
    logic [7:0] max_addr, max_data;
    logic       max_start, max_rst, max_busy;

    display_driver u_drv (
        .clk      (clk),
        .rst_n    (rst_n),
        .segments (segments),
        .max_addr (max_addr),
        .max_data (max_data),
        .max_start(max_start),
        .max_rst  (max_rst),
        .max_busy (max_busy)
    );

    // ── max7219 (existing Verilog) ───────────────────────────────────────────
    max7219 u_max (
        .clk     (clk),
        .rst     (max_rst),
        .addr_in (max_addr),
        .din     (max_data),
        .start   (max_start),
        .cs      (spi_cs),
        .dout    (spi_din),
        .sck     (spi_clk),
        .busy    (max_busy)
    );

    // ── LED / buzzer driver ──────────────────────────────────────────────────
    led_buzzer_driver u_leds (
        .clk          (clk),
        .rst_n        (rst_n),
        .led_work_in  (led_work_in),
        .led_break_in (led_break_in),
        .buzzer_en_in (buzzer_en_in),
        .led_work     (led_work),
        .led_break    (led_break),
        .buzzer       (buzzer)
    );

endmodule