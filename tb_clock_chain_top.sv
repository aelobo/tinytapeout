// =============================================================================
//
// Testbench for clock_chain_top 

// Uses CLK_FREQ=10 so the divider ticks every 10 cycles, making simulation
// fast while still exercising the full carry chain.
//
// Tests
//   1. Reset check          – all outputs at known reset values
//   2. Tick generation      – clk_divider fires tick_1hz every CLK_FREQ cycles
//   3. Sec rollover         – 59->0 and carry_sec asserted
//   4. Min carry            – carry from sec propagates into min_counter
//   5. Hour carry           – carry from min propagates into hour_counter
//   6. Day/month chain      – hour carry ripples to day then month
//   7. Feb leap / non-leap  – rollover module drives correct max_days for Feb
//   8. Setup write-enables  – btn_up/dn + we_* manually adjust each field
// =============================================================================

module tb_clock_chain_top;


    localparam int CLK_FREQ  = 10;
    localparam int CLK_PERIOD = 10;   // ns

    // DUT ports
    logic        clk;
    logic        rst_n;
    logic        btn_up;
    logic        btn_dn;
    logic        we_sec, we_min, we_hr, we_day, we_mon;
    logic        leap_year;
    logic [5:0]  sec;
    logic [5:0]  min;
    logic [4:0]  hour;
    logic [4:0]  day;
    logic [3:0]  month;

    // DUT 
    clock_chain_top #(.CLK_FREQ(CLK_FREQ)) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .btn_up    (btn_up),
        .btn_dn    (btn_dn),
        .we_sec    (we_sec),
        .we_min    (we_min),
        .we_hr     (we_hr),
        .we_day    (we_day),
        .we_mon    (we_mon),
        .leap_year (leap_year),
        .sec       (sec),
        .min       (min),
        .hour      (hour),
        .day       (day),
        .month     (month)
    );

    // Clock gen
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // Helper tasks
    // -------------------------------------------------------------------------

    // Apply reset for a few cycles
    task automatic apply_reset();
        rst_n = 0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
    endtask

    // Advance simulation by N complete 1 Hz ticks
    task automatic wait_ticks(input int n);
        repeat (n * CLK_FREQ) @(posedge clk);
    endtask

    // Pulse btn_up for one clock cycle with a given write-enable
    task automatic pulse_up(input logic we_sig);
        @(negedge clk);
        btn_up = 1;
        @(posedge clk);
        @(negedge clk);
        btn_up = 0;
    endtask

    // Pulse btn_dn for one clock cycle
    task automatic pulse_dn();
        @(negedge clk);
        btn_dn = 1;
        @(posedge clk);
        @(negedge clk);
        btn_dn = 0;
    endtask

    // Simple assertion helper
    int pass_count = 0;
    int fail_count = 0;

    task automatic check(
        input string  test_name,
        input logic   condition
    );
        if (condition) begin
            $display("[PASS] %s", test_name);
            pass_count++;
        end else begin
            $display("[FAIL] %s  (time=%0t)", test_name, $time);
            fail_count++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------------------------
    initial begin
        // Default input state
        rst_n     = 1;
        btn_up    = 0;
        btn_dn    = 0;
        we_sec    = 0;
        we_min    = 0;
        we_hr     = 0;
        we_day    = 0;
        we_mon    = 0;
        leap_year = 0;

        $display("=== tb_clock_chain_top starting ===");

        // ---------------------------------------------------------------------
        // TEST 1 – Reset check
        // ---------------------------------------------------------------------
        apply_reset();
        @(posedge clk); #1;
        check("T1a: sec resets to 0",     sec   == 6'd0);
        check("T1b: min resets to 0",     min   == 6'd0);
        check("T1c: hour resets to 0",    hour  == 5'd0);
        check("T1d: day resets to 1",     day   == 5'd1);
        check("T1e: month resets to 1",   month == 4'd1);

        // ---------------------------------------------------------------------
        // TEST 2 - Tick generation 
        // ---------------------------------------------------------------------

        wait_ticks(1);
        @(posedge clk); #1;
        check("T2: sec increments to 1 after one tick", sec == 6'd1);

        // ---------------------------------------------------------------------
        // TEST 3 – Seconds rollover (59 -> 0) and carry propagation to min
        // ---------------------------------------------------------------------
        wait_ticks(58);
        @(posedge clk); #1;
        check("T3a: sec reaches 59",  sec == 6'd59);
        check("T3b: min still 0",     min  == 6'd0);

        // sec wraps to 0 and min becomes 1
        wait_ticks(1);
        @(posedge clk); #1;
        check("T3c: sec wraps to 0 after 60 ticks", sec == 6'd0);
        check("T3d: min increments via carry",       min == 6'd1);

        // ---------------------------------------------------------------------
        // TEST 4 – Min -> Hour carry chain
        // ---------------------------------------------------------------------
        // sec=0, min=1, hour=0
        // advance 59 more minutes (59 * 60 ticks) so min rolls from 59->0 and hour increments to 1
        wait_ticks(59 * 60);
        @(posedge clk); #1;
        check("T4a: min wraps to 0 at 60th minute",   min  == 6'd0);
        check("T4b: hour increments to 1 via carry",  hour == 5'd1);

        // ---------------------------------------------------------------------
        // TEST 5 – Hour -> Day carry chain
        // ---------------------------------------------------------------------
        // advance 23 more hours (23 * 3600 ticks)
        // hour should roll 23->0 and day should go 1->2
        wait_ticks(23 * 60 * 60);
        @(posedge clk); #1;
        check("T5a: hour wraps to 0 after 24 h",  hour == 5'd0);
        check("T5b: day increments to 2",         day  == 5'd2);

        // ---------------------------------------------------------------------
        // TEST 6 – Day -> Month carry
        // ---------------------------------------------------------------------
        // switch month to April using write enable
        // currently month=1, we need month=4
        // use we_mon + btn_up to bump month by 3
        we_mon = 1;
        repeat (3) begin
            pulse_up(we_mon);
            repeat (2) @(posedge clk);  // let FF settle
        end
        we_mon = 0;
        @(posedge clk); #1;
        check("T6a: month manually set to 4", month == 4'd4);

        // set day to 30
        we_day = 1;
        repeat (28) begin
            pulse_up(we_day);
            repeat (2) @(posedge clk);
        end
        we_day = 0;
        @(posedge clk); #1;
        check("T6b: day manually set to 30", day == 5'd30);

        // advance one full day (24 * 3600 ticks)
        // day should roll 30->1 and month should become 5
        wait_ticks(24 * 60 * 60);
        @(posedge clk); #1;
        check("T6c: day wraps to 1 (April->May boundary)", day   == 5'd1);
        check("T6d: month increments to 5",                month == 4'd5);

        // ---------------------------------------------------------------------
        // TEST 7 – February leap-year / non-leap-year max days
        // ---------------------------------------------------------------------
        // set month=2 with we_mon currently month=5; go back to 2 with dec x3
        we_mon = 1;
        repeat (3) begin
            pulse_dn();
            repeat (2) @(posedge clk);
        end
        we_mon = 0;
        @(posedge clk); #1;
        check("T7a: month set to 2 (February)", month == 4'd2);

        // non-leap year: advance to day=28 via manual setup, then free-run one
        // day – should roll to day=1 and bump month to 3
        we_day = 1;
        // day is 1; inc to 28 means 27 pulses
        repeat (27) begin
            pulse_up(we_day);
            repeat (2) @(posedge clk);
        end
        we_day = 0;
        @(posedge clk); #1;
        check("T7b: day set to 28 (non-leap Feb)", day == 5'd28);

        leap_year = 0;
        wait_ticks(24 * 60 * 60);
        @(posedge clk); #1;
        check("T7c: day rolls at 28 (non-leap year)", day   == 5'd1);
        check("T7d: month advances to 3 from Feb",    month == 4'd3);

        // leap year: set month=2, day=29, y -> should roll to March
        // first set month back to Feb (March=3, need to dec by 1)
        we_mon = 1;
        pulse_dn();
        repeat (2) @(posedge clk);
        we_mon = 0;
        @(posedge clk); #1;
        check("T7e: month back to 2 for leap test", month == 4'd2);

        // set day to 29 (currently 1, inc 28 times)
        we_day = 1;
        leap_year = 1;
        repeat (28) begin
            pulse_up(we_day);
            repeat (2) @(posedge clk);
        end
        we_day = 0;
        @(posedge clk); #1;
        check("T7f: day reaches 29 (leap year)",   day == 5'd29);

        wait_ticks(24 * 60 * 60);
        @(posedge clk); #1;
        check("T7g: day rolls at 29 (leap year)",  day   == 5'd1);
        check("T7h: month advances to 3 from leap Feb", month == 4'd3);
        leap_year = 0;

        // ---------------------------------------------------------------------
        // TEST 8 – Setup write-enables: sec inc/dec
        // ---------------------------------------------------------------------
        apply_reset();
        @(posedge clk); #1;

        we_sec = 1;
        repeat (5) begin
            pulse_up(we_sec);
            repeat (2) @(posedge clk);
        end
        we_sec = 0;
        @(posedge clk); #1;
        check("T8a: sec manually incremented to 5", sec == 6'd5);

        we_sec = 1;
        repeat (3) begin
            pulse_dn();
            repeat (2) @(posedge clk);
        end
        we_sec = 0;
        @(posedge clk); #1;
        check("T8b: sec manually decremented to 2", sec == 6'd2);

        we_sec = 1;
        repeat (57) begin
            pulse_up(we_sec);
            repeat (2) @(posedge clk);
        end
        we_sec = 0;
        @(posedge clk); #1;
        check("T8c: sec at 59 before wrap-up test", sec == 6'd59);

        we_sec = 1;
        pulse_up(we_sec);
        repeat (2) @(posedge clk);
        we_sec = 0;
        @(posedge clk); #1;
        check("T8d: sec wraps 59->0 via btn_up",  sec == 6'd0);

        we_sec = 1;
        pulse_dn();
        repeat (2) @(posedge clk);
        we_sec = 0;
        @(posedge clk); #1;
        check("T8e: sec wraps 0->59 via btn_dn",  sec == 6'd59);

        // ---------------------------------------------------------------------
        // TEST 9 – Setup write-enables ignored when tick_1hz is active
        //           (we_sec=0, free-run must not be affected by btn_up)
        // ---------------------------------------------------------------------
        apply_reset();
        btn_up = 1;    // btn_up held high but we_sec=0 -> should be ignored
        wait_ticks(1);
        @(posedge clk); #1;
        btn_up = 0;
        check("T9: free-run ignores btn_up when we_sec=0", sec == 6'd1);

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
        $dumpfile("tb_clock_chain_top.vcd");
        $dumpvars(0, tb_clock_chain_top);
    end

endmodule