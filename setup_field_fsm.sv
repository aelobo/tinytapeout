// =============================================================================
// setup_field_fsm
//
// active only when in_setup  asserted by main_mode_fsm
// btn_set cycles through the fields that can be changed
// setup_is_date selects which field set is avail:
//      time fields  (setup_is_date=0): SEL_MIN  --> SEL_HOUR --> SEL_MIN ...
//      date fields  (setup_is_date=1): SEL_DAY  --> SEL_MON  --> SEL_DAY ...
//
// btn_up / btn_dn increment / decrement the selected field
// corresponding we_* output  asserted for one cycle per button press
//
// Outputs:
//      field_sel[1:0]                     – which field highlighted on display
//      we_min / we_hr / we_day / we_mon   – write-enables to clock_chain_top
// =============================================================================


module setup_field_fsm (
    input  logic       clk,
    input  logic       rst_n,

    input  logic       in_setup,      
    input  logic       setup_is_date, 
    input  logic       btn_set,         // advance to next field
    input  logic       btn_up,          // increment current field
    input  logic       btn_dn,          // decrement current field

    output logic [1:0] field_sel,       // 00=MIN 01=HOUR 10=DAY 11=MON
    output logic       we_min,
    output logic       we_hr,
    output logic       we_day,
    output logic       we_mon
);

    typedef enum logic [1:0] {
        SEL_MIN  = 2'b00,
        SEL_HOUR = 2'b01,
        SEL_DAY  = 2'b10,
        SEL_MON  = 2'b11
    } field_state_t;

    field_state_t state, next;

    // state
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= SEL_MIN;
        else        state <= next;
    end

    // next state logic
    always_comb begin
        next = state;

        if (!in_setup) begin
            // When not in setup, park at the correct starting field
            next = field_state_t'(setup_is_date ? SEL_DAY : SEL_MIN);
        end else if (btn_set) begin
            case (state)
                // time fields cycle: MIN <-> HOUR
                SEL_MIN:  next = SEL_HOUR;
                SEL_HOUR: next = SEL_MIN;
                // date fields cycle: DAY <-> MON
                SEL_DAY:  next = SEL_MON;
                SEL_MON:  next = SEL_DAY;
                default:  next = SEL_MIN;
            endcase
        end
    end

    // output logic
    always_comb begin
        field_sel = 2'b00;
        we_min    = 1'b0;
        we_hr     = 1'b0;
        we_day    = 1'b0;
        we_mon    = 1'b0;

        if (in_setup) begin
            case (state)
                SEL_MIN: begin
                    field_sel = 2'b00;
                    we_min    = btn_up | btn_dn;
                end
                SEL_HOUR: begin
                    field_sel = 2'b01;
                    we_hr     = btn_up | btn_dn;
                end
                SEL_DAY: begin
                    field_sel = 2'b10;
                    we_day    = btn_up | btn_dn;
                end
                SEL_MON: begin
                    field_sel = 2'b11;
                    we_mon    = btn_up | btn_dn;
                end
                default: field_sel = 2'b00;
            endcase
        end
    end

endmodule