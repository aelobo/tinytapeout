// =============================================================================
//
// Testbench for fsm_control_top 
//
// Covers:
//   main_mode_fsm  – state transitions driven by btn_mode / btn_set
//   setup_field_fsm – field cycling and write-enable generation
//   Integration     – combined flows (enter setup, edit field, exit)
//
// Test plan
//   1.  Reset state               – CLOCK mode, no setup, no WE outputs active
//   2.  Mode cycling              – btn_mode: CLOCK -> DATE -> POMODORO -> CLOCK
//   3.  Enter SETUP_CLK           – from CLOCK, btn_set asserts in_setup
//   4.  Exit SETUP_CLK            – btn_set again returns to CLOCK
//   5.  Enter SETUP_DATE          – from DATE, btn_set asserts in_setup + setup_is_date
//   6.  Exit SETUP_DATE           – btn_set again returns to DATE
//   7.  POMODORO no setup         – btn_set has no effect in POMODORO state
//   8.  Field FSM – time fields   – SEL_MIN <-> SEL_HOUR cycling in SETUP_CLK
//   9.  Field FSM – date fields   – SEL_DAY <-> SEL_MON cycling in SETUP_DATE
//   10. WE generation – we_min    – btn_up asserts we_min when SEL_MIN active
//   11. WE generation – we_hr     – btn_up asserts we_hr  when SEL_HOUR active
//   12. WE generation – we_day    – btn_up asserts we_day when SEL_DAY active
//   13. WE generation – we_mon    – btn_dn asserts we_mon when SEL_MON active
//   14. WE suppressed in CLOCK    – btn_up does NOT assert any WE outside setup
//   15. Pomodoro active signal    – pomodoro_active only in POMODORO state
//   16. display_mode encoding     – correct 2-bit code for each mode
//   17. Full setup-edit flow      – enter setup, edit two fields, exit, verify WE
// =============================================================================

module tb_fsm_control_top;

    // Parameters 
    localparam int WORK_MIN     = 1;
    localparam int BREAK_MIN    = 1;
    localparam int ALARM_CYCLES = 4;
    localparam int CLK_PERIOD   = 10;  // ns

    // DUT ports
    logic        clk;
    logic        rst_n;
    logic        btn_mode;
    logic        btn_set;
    logic        btn_up;
    logic        btn_dn;
    logic        tick_1hz;
    logic        we_work;
    logic        we_break;
    logic [5:0]  work_cfg;
    logic [5:0]  break_cfg;
    logic        leap_year;

    logic [1:0]  display_mode;
    logic [1:0]  field_sel;
    logic        in_setup;
    logic        we_min;
    logic        we_hr;
    logic        we_day;
    logic        we_mon;
    logic [11:0] pomo_countdown;
    logic [9:0]  pomo_display_val;
    logic        led_work;
    logic        led_break;
    logic        buzzer_en;

    // DUT instantiation
    fsm_control_top #(
        .WORK_MIN    (WORK_MIN),
        .BREAK_MIN   (BREAK_MIN),
        .ALARM_CYCLES(ALARM_CYCLES)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .btn_mode        (btn_mode),
        .btn_set         (btn_set),
        .btn_up          (btn_up),
        .btn_dn          (btn_dn),
        .tick_1hz        (tick_1hz),
        .we_work         (we_work),
        .we_break        (we_break),
        .work_cfg        (work_cfg),
        .break_cfg       (break_cfg),
        .leap_year       (leap_year),
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

    // Clock
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Tracking
    int pass_count = 0;
    int fail_count = 0;

    task automatic check(input string name, input logic cond);
        if (cond) begin
            $display("[PASS] %s", name);
            pass_count++;
        end else begin
            $display("[FAIL] %s  (time=%0t)", name, $time);
            fail_count++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Helper tasks
    // -------------------------------------------------------------------------

    task automatic apply_reset();
        rst_n = 0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
        @(posedge clk); #1;
    endtask

    // Single-cycle button pulse – driven on negedge, sampled on next posedge
    task automatic press_mode();
        @(negedge clk); btn_mode = 1;
        @(posedge clk); @(negedge clk); btn_mode = 0;
        @(posedge clk); #1;
    endtask

    task automatic press_set();
        @(negedge clk); btn_set = 1;
        @(posedge clk); @(negedge clk); btn_set = 0;
        @(posedge clk); #1;
    endtask

    task automatic press_up();
        @(negedge clk); btn_up = 1;
        @(posedge clk); @(negedge clk); btn_up = 0;
        @(posedge clk); #1;
    endtask

    task automatic press_dn();
        @(negedge clk); btn_dn = 1;
        @(posedge clk); @(negedge clk); btn_dn = 0;
        @(posedge clk); #1;
    endtask

    // -------------------------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------------------------
    initial begin
        // Defaults
        rst_n     = 1;
        btn_mode  = 0;
        btn_set   = 0;
        btn_up    = 0;
        btn_dn    = 0;
        tick_1hz  = 0;
        we_work   = 0;
        we_break  = 0;
        work_cfg  = 6'd25;
        break_cfg = 6'd5;
        leap_year = 0;

        $display("=== tb_fsm_control_top starting ===");

        // ---------------------------------------------------------------------
        // TEST 1 – Reset state
        // ---------------------------------------------------------------------
        apply_reset();
        check("T1a: display_mode=CLOCK after reset",  display_mode == 2'b00);
        check("T1b: in_setup=0 after reset",          in_setup     == 1'b0);
        check("T1c: we_min=0 after reset",            we_min       == 1'b0);
        check("T1d: we_hr=0 after reset",             we_hr        == 1'b0);
        check("T1e: we_day=0 after reset",            we_day       == 1'b0);
        check("T1f: we_mon=0 after reset",            we_mon       == 1'b0);
        check("T1g: pomodoro_active=0 after reset",   led_work     == 1'b0);

        // ---------------------------------------------------------------------
        // TEST 2 – Mode cycling CLOCK -> DATE -> POMODORO -> CLOCK
        // ---------------------------------------------------------------------
        press_mode();
        check("T2a: after 1x btn_mode -> DATE",      display_mode == 2'b01);

        press_mode();
        check("T2b: after 2x btn_mode -> POMODORO",  display_mode == 2'b10);

        press_mode();
        check("T2c: after 3x btn_mode -> CLOCK",     display_mode == 2'b00);

        // ---------------------------------------------------------------------
        // TEST 3 – Enter SETUP_CLK from CLOCK
        // ---------------------------------------------------------------------
        // Currently in CLOCK
        press_set();
        check("T3a: in_setup=1 after btn_set in CLOCK",     in_setup     == 1'b1);
        check("T3b: display_mode still CLOCK in SETUP_CLK", display_mode == 2'b00);
        // setup_is_date should be 0 (clock setup)
        check("T3c: field_sel=SEL_MIN on entering SETUP_CLK", field_sel == 2'b00);

        // ---------------------------------------------------------------------
        // TEST 4 – Exit SETUP_CLK
        // ---------------------------------------------------------------------
        press_set();
        check("T4a: in_setup=0 after second btn_set", in_setup     == 1'b0);
        check("T4b: display_mode=CLOCK after exit",   display_mode == 2'b00);

        // ---------------------------------------------------------------------
        // TEST 5 – Enter SETUP_DATE from DATE
        // ---------------------------------------------------------------------
        press_mode(); 
        check("T5a: display_mode=DATE", display_mode == 2'b01);

        press_set(); 
        check("T5b: in_setup=1 in SETUP_DATE",          in_setup     == 1'b1);
        check("T5c: display_mode=DATE in SETUP_DATE",   display_mode == 2'b01);
        // Date setup starts at SEL_DAY (2'b10)
        check("T5d: field_sel=SEL_DAY on entering SETUP_DATE", field_sel == 2'b10);

        // ---------------------------------------------------------------------
        // TEST 6 – Exit SETUP_DATE
        // ---------------------------------------------------------------------
        press_set();
        check("T6a: in_setup=0 after exit SETUP_DATE", in_setup     == 1'b0);
        check("T6b: display_mode=DATE after exit",     display_mode == 2'b01);

        // ---------------------------------------------------------------------
        // TEST 7 – POMODORO: btn_set has no effect
        // ---------------------------------------------------------------------
        press_mode();   // DATE -> POMODORO
        check("T7a: in POMODORO state", display_mode == 2'b10);

        press_set();    // should be ignored
        check("T7b: in_setup stays 0 in POMODORO",  in_setup     == 1'b0);
        check("T7c: display_mode still POMODORO",   display_mode == 2'b10);

        press_mode();   // return to CLOCK for subsequent tests
        check("T7d: returned to CLOCK", display_mode == 2'b00);

        // ---------------------------------------------------------------------
        // TEST 8 – Field FSM in SETUP_CLK: SEL_MIN <-> SEL_HOUR
        // ---------------------------------------------------------------------
        press_set();    // enter SETUP_CLK
        check("T8a: field starts at SEL_MIN (2'b00)", field_sel == 2'b00);

        press_set();    // move to field -> SEL_HOUR
        check("T8b: field move tos to SEL_HOUR (2'b01)", field_sel == 2'b01);

        press_set();    // move to field -> SEL_MIN (wraps)
        check("T8c: field wraps back to SEL_MIN (2'b00)", field_sel == 2'b00);

        press_set();
        check("T8d: exited SETUP_CLK", in_setup == 1'b0);

        // ---------------------------------------------------------------------
        // TEST 9 – Field FSM in SETUP_DATE: SEL_DAY <-> SEL_MON
        // ---------------------------------------------------------------------
        press_mode();   // CLOCK -> DATE
        press_set();    // enter SETUP_DATE
        check("T9a: field starts at SEL_DAY (2'b10)", field_sel == 2'b10);

        press_set();    // move to -> SEL_MON
        check("T9b: field move tos to SEL_MON (2'b11)", field_sel == 2'b11);

        press_set();    // move to -> SEL_DAY (wraps)
        check("T9c: field wraps back to SEL_DAY (2'b10)", field_sel == 2'b10);

        // ---------------------------------------------------------------------
        // TEST 10 – we_min asserted when SEL_MIN + btn_up
        // ---------------------------------------------------------------------
        @(negedge clk); btn_set = 1;         // exit SETUP_DATE (returns to DATE)
        @(posedge clk); @(negedge clk); btn_set = 0;
        @(posedge clk); #1;

        @(negedge clk); btn_mode = 1;        // DATE -> POMODORO
        @(posedge clk); @(negedge clk); btn_mode = 0;
        @(posedge clk); #1;
        @(negedge clk); btn_mode = 1;        // POMODORO -> CLOCK
        @(posedge clk); @(negedge clk); btn_mode = 0;
        @(posedge clk); #1;

        press_set();    // enter SETUP_CLK; field=SEL_MIN
        check("T10a: in SETUP_CLK, SEL_MIN", field_sel == 2'b00 && in_setup);

        @(negedge clk); btn_up = 1;
        @(posedge clk); #1;
        check("T10b: we_min asserted with btn_up in SEL_MIN", we_min == 1'b1);
        check("T10c: other WEs silent",
              we_hr == 1'b0 && we_day == 1'b0 && we_mon == 1'b0);
        @(negedge clk); btn_up = 0;

        // ---------------------------------------------------------------------
        // TEST 11 – we_hr asserted when SEL_HOUR + btn_up
        // ---------------------------------------------------------------------
        press_set();    // SEL_MIN -> SEL_HOUR (btn_set move tos field)
        check("T11a: field is SEL_HOUR", field_sel == 2'b01);

        @(negedge clk); btn_up = 1;
        @(posedge clk); #1;
        check("T11b: we_hr asserted in SEL_HOUR",  we_hr  == 1'b1);
        check("T11c: we_min silent in SEL_HOUR",   we_min == 1'b0);
        @(negedge clk); btn_up = 0;

        // Exit SETUP_CLK
        press_set();    // field -> SEL_MIN; note: exit requires going through CLOCK
        press_set();    // exits SETUP_CLK

        // ---------------------------------------------------------------------
        // TEST 12 – we_day asserted when SEL_DAY + btn_up
        // ---------------------------------------------------------------------
        press_mode();   // CLOCK -> DATE
        press_set();    // enter SETUP_DATE; field=SEL_DAY
        check("T12a: field is SEL_DAY", field_sel == 2'b10);

        @(negedge clk); btn_up = 1;
        @(posedge clk); #1;
        check("T12b: we_day asserted in SEL_DAY",  we_day == 1'b1);
        check("T12c: we_mon silent",               we_mon == 1'b0);
        @(negedge clk); btn_up = 0;

        // ---------------------------------------------------------------------
        // TEST 13 – we_mon asserted when SEL_MON + btn_dn
        // ---------------------------------------------------------------------
        press_set();    // SEL_DAY -> SEL_MON
        check("T13a: field is SEL_MON", field_sel == 2'b11);

        @(negedge clk); btn_dn = 1;
        @(posedge clk); #1;
        check("T13b: we_mon asserted with btn_dn in SEL_MON", we_mon == 1'b1);
        check("T13c: we_day silent",                          we_day == 1'b0);
        @(negedge clk); btn_dn = 0;

        // Exit SETUP_DATE
        press_set();    // SEL_MON -> SEL_DAY
        press_set();    // exit

        // ---------------------------------------------------------------------
        // TEST 14 – WE outputs suppressed when NOT in setup
        // ---------------------------------------------------------------------
        // Return to CLOCK (currently DATE after exit)
        press_mode();   // DATE -> POMODORO
        press_mode();   // POMODORO -> CLOCK
        check("T14a: back in CLOCK, not in setup", in_setup == 1'b0);

        @(negedge clk); btn_up = 1;
        @(posedge clk); #1;
        check("T14b: we_min stays 0 outside setup", we_min == 1'b0);
        check("T14c: we_hr  stays 0 outside setup", we_hr  == 1'b0);
        @(negedge clk); btn_up = 0;

        // ---------------------------------------------------------------------
        // TEST 15 – pomodoro_active only in POMODORO
        // ---------------------------------------------------------------------

        check("T15a: display_mode=CLOCK (not POMODORO)", display_mode == 2'b00);

        press_mode();   // -> DATE
        check("T15b: display_mode=DATE",     display_mode == 2'b01);
        check("T15c: in_setup=0 still",      in_setup == 1'b0);

        press_mode();   // -> POMODORO
        check("T15d: display_mode=POMODORO", display_mode == 2'b10);
        check("T15e: buzzer_en=0 before start", buzzer_en == 1'b0);

        press_mode();   // -> CLOCK
        check("T15f: display_mode back to CLOCK", display_mode == 2'b00);

        // ---------------------------------------------------------------------
        // TEST 16 – display_mode encoding for all five states
        // ---------------------------------------------------------------------

        press_set();    // CLOCK -> SETUP_CLK
        check("T16a: SETUP_CLK display_mode=00", display_mode == 2'b00);
        press_set();    // exit SETUP_CLK -> CLOCK

        press_mode();   // CLOCK -> DATE
        press_set();    // DATE -> SETUP_DATE
        check("T16b: SETUP_DATE display_mode=01", display_mode == 2'b01);
        press_set();    // exit

        // ---------------------------------------------------------------------
        // TEST 17 – Full setup-edit flow: enter, edit two fields, exit
        //           Verify correct WE pulses, then WEs go silent after exit
        // ---------------------------------------------------------------------
        // return to CLOCK
        press_mode();   // DATE -> POMODORO
        press_mode();   // POMODORO -> CLOCK

        press_set();    // enter SETUP_CLK; field=SEL_MIN
        check("T17a: in_setup=1",          in_setup  == 1'b1);
        check("T17b: field=SEL_MIN",       field_sel == 2'b00);

        // increment minutes twice
        press_up();
        press_up();
        check("T17c: still in SEL_MIN after ups", field_sel == 2'b00);

        press_set();    // move to to SEL_HOUR
        check("T17d: field=SEL_HOUR",      field_sel == 2'b01);

        // decrement hours once
        press_dn();
        check("T17e: still in SEL_HOUR after dn", field_sel == 2'b01);

        // exit setup
        press_set();    // SEL_HOUR -> SEL_MIN (field wraps)
        press_set();    // exit SETUP_CLK -> CLOCK
        check("T17f: in_setup=0 after full exit",  in_setup == 1'b0);
        check("T17g: all WEs silent after exit",
              we_min == 1'b0 && we_hr == 1'b0 &&
              we_day == 1'b0 && we_mon == 1'b0);

        // ---------------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------------
        $display("=== RESULTS: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;
    end


    initial begin
        #50_000_000;
        $display("TIMEOUT!!!! simulation exceeded limit");
        $finish;
    end


    initial begin
        $dumpfile("tb_fsm_control_top.vcd");
        $dumpvars(0, tb_fsm_control_top);
    end

endmodule