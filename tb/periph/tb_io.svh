// Shared bench scaffolding, included inside each bench module: 48 MHz
// clk, synchronous reset, ce_pit (/39) and ce_usart (/24), a Z8001-style
// I/O bus and the mainboard's two-pulse VI acknowledge, plus a
// scoreboard.  Bus timing: CPU clock = 12 clk (4 MHz); an I/O transaction
// is 4 T-states (address 12 clk, /DS 30 clk).  io_rd/io_wr and the chip
// select drop in the same clock as the *_end pulse (the latest the
// mainboard can sample), so read data must be held by the device.

logic clk = 1'b0;
always #10.4167 clk = ~clk;

logic rst_n = 1'b0;

longint cyc = 0;                     // clk count
always @(posedge clk) cyc <= cyc + 1;

// Clock enables, as the mainboard makes them.
logic [5:0] ce_pit_cnt = 6'd0;
logic [4:0] ce_usart_cnt = 5'd0;
logic       ce_pit = 1'b0, ce_usart = 1'b0;
always @(posedge clk) begin
  ce_pit_cnt   <= (ce_pit_cnt == 6'd38) ? 6'd0 : ce_pit_cnt + 6'd1;
  ce_usart_cnt <= (ce_usart_cnt == 5'd23) ? 5'd0 : ce_usart_cnt + 5'd1;
  ce_pit       <= ce_pit_cnt == 6'd38;
  ce_usart     <= ce_usart_cnt == 5'd23;
end

// I/O bus
logic [15:0] io_addr  = 16'h0000;
logic [15:0] io_wdata = 16'h0000;
logic        io_rd = 1'b0, io_wr = 1'b0, io_rd_end = 1'b0, io_wr_end = 1'b0;
logic        bus_on = 1'b0;
logic        pic_inta_n = 1'b1;

wire board = bus_on && (io_addr[15:11] == 5'd0);
wire cs_ppi = board && io_addr[8:5] == 4'b0100;   // 0x80
wire cs_kbd = board && io_addr[8:5] == 4'b0101;   // 0xA0
wire cs_ser = board && io_addr[8:5] == 4'b0110;   // 0xC0
wire cs_pit = board && io_addr[8:5] == 4'b1001;   // 0x120
wire cs_pic = board && io_addr[8:5] == 4'b1010;   // 0x140

// Each bench drives rd_mux from its devices (by io_addr, which is held).
logic [15:0] rd_mux;

int errors = 0;
int checks = 0;

task automatic check(input string what, input longint got, input longint exp);
  checks++;
  if (got !== exp) begin
    errors++;
    $display("FAIL %s: got %0h expected %0h (t=%0t)", what, got, exp, $time);
  end
endtask

task automatic check_range(input string what, input longint got, input longint lo, input longint hi);
  checks++;
  if (got < lo || got > hi) begin
    errors++;
    $display("FAIL %s: got %0h expected %0h..%0h (t=%0t)", what, got, lo, hi, $time);
  end
endtask

task automatic finish();
  if (errors == 0) $display("%0d checks\nPASS", checks);
  else             $fatal(1, "%0d of %0d checks failed", errors, checks);
  $finish;
endtask

// Not for concurrent processes: Verilator 5.020 (--timing) shares the
// repeat count between simultaneous calls; use an inline repeat there.
task automatic clocks(input int n);
  repeat (n) @(posedge clk);
endtask

// Idle CPU clocks (12 clk each).
task automatic cpu(input int n);
  if (n > 0) clocks(12 * n);
endtask

task automatic reset_dut();
  rst_n <= 1'b0;
  clocks(10);
  rst_n <= 1'b1;
  clocks(10);
endtask

task automatic io_write(input logic [15:0] a, input logic [15:0] d);
  @(posedge clk);
  io_addr  <= a;
  io_wdata <= d;
  bus_on   <= 1'b1;
  clocks(12);
  io_wr <= 1'b1;
  clocks(30);
  io_wr     <= 1'b0;
  bus_on    <= 1'b0;
  io_wr_end <= 1'b1;
  @(posedge clk);
  io_wr_end <= 1'b0;
  clocks(4);
endtask

task automatic io_read(input logic [15:0] a, output logic [15:0] d);
  @(posedge clk);
  io_addr <= a;
  bus_on  <= 1'b1;
  clocks(12);
  io_rd <= 1'b1;
  clocks(30);
  io_rd     <= 1'b0;
  bus_on    <= 1'b0;
  io_rd_end <= 1'b1;
  #1 d = rd_mux;                     // the /DS-rise clock
  @(posedge clk);
  io_rd_end <= 1'b0;
  clocks(3);
endtask

task automatic io_read8(input logic [15:0] a, output logic [7:0] d);
  logic [15:0] w;
  io_read(a, w);
  d = w[7:0];
endtask

// Status-0111 acknowledge: first /INTA one CPU clock long, two CPU clock
// edges after /AS; the second is the CPU's /DS read of the identifier.
// Returns the word seen at the /DS rise; low_word is the word while low.
task automatic inta_cycle(output logic [15:0] id, output logic [15:0] low_word);
  @(posedge clk);
  clocks(24);
  pic_inta_n <= 1'b0;
  clocks(12);
  pic_inta_n <= 1'b1;
  clocks(24);
  pic_inta_n <= 1'b0;
  clocks(29);
  #1 low_word = rd_mux;
  @(posedge clk);
  pic_inta_n <= 1'b1;
  #1 id = rd_mux;
  clocks(12);
endtask
