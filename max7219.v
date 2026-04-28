// =============================================================================
// max7219 implementation
//      - used this RTL for my 18500 project in Spring 2026
//      - https://github.com/cerkit/max7219TinyFPGA
//
// =============================================================================


/*
   Parameters:
     SIZE = 8
     DIV = 0
     TOP = 0
     UP = 1
*/
module counter (
    input clk,
    input rst,
    output reg [7:0] value
  );

  // These are non-functional until I learn what they're for
  parameter SIZE = 4'h8;
  parameter DIV = 1'h0;
  parameter TOP = 1'h0;
  parameter UP = 1'h1;


  reg [7:0] M_ctr_d, M_ctr_q = 1'h0;

  localparam MAX_VALUE = 1'h0;

  always @* begin
    M_ctr_d = M_ctr_q;

    value = M_ctr_q[0+7-:8];
    if (1'h1) begin
      M_ctr_d = M_ctr_q + 1'h1;
      if (1'h0 && M_ctr_q == 1'h0) begin
        M_ctr_d = 1'h0;
      end
    end else begin
      M_ctr_d = M_ctr_q - 1'h1;
      if (1'h0 && M_ctr_q == 1'h0) begin
        M_ctr_d = 1'h0;
      end
    end
  end

  always @(posedge clk) begin
    if (rst == 1'b1) begin
      M_ctr_q <= 1'h0;
    end else begin
      M_ctr_q <= M_ctr_d;
    end
  end

endmodule


/*
   Parameters:
     CLK_DIV = 8
     CPOL = 0
     CPHA = 0
*/
module spi_master (
    input clk,
    input rst,
    input miso,
    output reg mosi,
    output reg sck,
    input start,
    input [7:0] data_in,
    output reg [7:0] data_out,
    output reg new_data,
    output reg busy
  );

  // These are currently non-functional until I learn what they're for
  localparam CLK_DIV = 4'h8;
  localparam CPOL = 1'h0;
  localparam CPHA = 1'h0;


  localparam IDLE_state = 1'd0;
  localparam TRANSFER_state = 1'd1;

  reg M_state_d, M_state_q = IDLE_state;
  reg [7:0] M_data_d, M_data_q = 1'h0;
  reg [7:0] M_sck_reg_d, M_sck_reg_q = 1'h0;
  reg M_mosi_reg_d, M_mosi_reg_q = 1'h0;
  reg [2:0] M_ctr_d, M_ctr_q = 1'h0;

  always @* begin
    M_state_d = M_state_q;
    M_mosi_reg_d = M_mosi_reg_q;
    M_sck_reg_d = M_sck_reg_q;
    M_data_d = M_data_q;
    M_ctr_d = M_ctr_q;

    new_data = 1'h0;
    busy = M_state_q != IDLE_state;
    data_out = M_data_q;
    sck = ((1'h0 ^ M_sck_reg_q[7+0-:1]) & (M_state_q == TRANSFER_state)) ^ 1'h0;
    mosi = M_mosi_reg_q;

    case (M_state_q)
      IDLE_state: begin
        M_sck_reg_d = 1'h0;
        M_ctr_d = 1'h0;
        if (start) begin
          M_data_d = data_in;
          M_state_d = TRANSFER_state;
        end
      end
      TRANSFER_state: begin
        M_sck_reg_d = M_sck_reg_q + 1'h1;
        if (M_sck_reg_q == 1'h0) begin
          M_mosi_reg_d = M_data_q[7+0-:1];
        end else begin
          if (M_sck_reg_q == 7'h7f) begin
            M_data_d = {M_data_q[0+6-:7], miso};
          end else begin
            if (M_sck_reg_q == 8'hff) begin
              M_ctr_d = M_ctr_q + 1'h1;
              if (M_ctr_q == 3'h7) begin
                M_state_d = IDLE_state;
                new_data = 1'h1;
              end
            end
          end
        end
      end
    endcase
  end

  always @(posedge clk) begin
    M_data_q <= M_data_d;
    M_sck_reg_q <= M_sck_reg_d;
    M_mosi_reg_q <= M_mosi_reg_d;
    M_ctr_q <= M_ctr_d;

    if (rst == 1'b1) begin
      M_state_q <= 1'h0;
    end else begin
      M_state_q <= M_state_d;
    end
  end

endmodule



module max7219 (
    input clk,
    input rst,
    input [7:0] addr_in,
    input [7:0] din,
    input start,
    output reg cs,
    output reg dout,
    output reg sck,
    output reg busy
  );



  localparam IDLE_state = 2'd0;
  localparam TRANSFER_ADDR_state = 2'd1;
  localparam TRANSFER_DATA_state = 2'd2;

  reg [1:0] M_state_d, M_state_q = IDLE_state;
  wire [1-1:0] M_spi_mosi;
  wire [1-1:0] M_spi_sck;
  wire [8-1:0] M_spi_data_out;
  wire [1-1:0] M_spi_new_data;
  wire [1-1:0] M_spi_busy;
  reg [1-1:0] M_spi_start;
  reg [8-1:0] M_spi_data_in;
  spi_master spi (
    .clk(clk),
    .rst(rst),
    .miso(1'h0),
    .start(M_spi_start),
    .data_in(M_spi_data_in),
    .mosi(M_spi_mosi),
    .sck(M_spi_sck),
    .data_out(M_spi_data_out),
    .new_data(M_spi_new_data),
    .busy(M_spi_busy)
  );
  reg [7:0] M_data_d, M_data_q = 1'h0;
  reg [7:0] M_addr_d, M_addr_q = 1'h0;
  reg M_load_state_d, M_load_state_q = 1'h0;

  reg [7:0] data_out;

  reg mosi;

  wire [8-1:0] M_count_value;
  reg [1-1:0] M_count_clk;
  reg [1-1:0] M_count_rst;
  counter count (
    .clk(M_count_clk),
    .rst(M_count_rst),
    .value(M_count_value)
  );

  always @* begin
    M_state_d = M_state_q;
    M_load_state_d = M_load_state_q;
    M_data_d = M_data_q;
    M_addr_d = M_addr_q;

    sck = M_spi_sck;
    M_count_clk = M_spi_sck;
    M_count_rst = 1'h0;
    data_out = 8'h00;
    M_spi_start = 1'h0;
    mosi = 1'h0;
    busy = M_state_q != IDLE_state;
    dout = 1'h0;

    case (M_state_q)
      IDLE_state: begin
        M_load_state_d = 1'h1;
        if (start) begin
          M_addr_d = addr_in;
          M_data_d = din;
          M_count_rst = 1'h1;
          M_load_state_d = 1'h0;
          M_state_d = TRANSFER_ADDR_state;
        end
      end
      TRANSFER_ADDR_state: begin
        M_spi_start = 1'h1;
        data_out = M_addr_q;
        dout = M_spi_mosi;
        if (M_count_value == 4'h8) begin
          M_state_d = TRANSFER_DATA_state;
        end
      end
      TRANSFER_DATA_state: begin
        M_spi_start = 1'h1;
        data_out = M_data_q;
        dout = M_spi_mosi;
        if (M_count_value == 5'h10) begin
          M_load_state_d = 1'h1;
          M_state_d = IDLE_state;
        end
      end
    endcase
    cs = M_load_state_q;
    M_spi_data_in = data_out;
  end

  always @(posedge clk) begin
    if (rst == 1'b1) begin
      M_data_q <= 1'h0;
      M_addr_q <= 1'h0;
      M_load_state_q <= 1'h0;
      M_state_q <= 1'h0;
    end else begin
      M_data_q <= M_data_d;
      M_addr_q <= M_addr_d;
      M_load_state_q <= M_load_state_d;
      M_state_q <= M_state_d;
    end
  end

endmodule

