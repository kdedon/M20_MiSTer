// m20_boot_rom: boot images of 8 KB (A13 ignored) and 16 KB, extension
// images filling sockets U55/U66.. in order, empty sockets and unused U36
// outputs reading 0xFFFF, and a new download forgetting the old size.
`default_nettype none
module tb_rom;
  logic clk = 1'b0;
  always #10 clk = ~clk;

  logic [2:0]  blk = 3'd0;
  logic [13:1] addr = '0;
  logic [15:0] q;
  logic        ld_start = 1'b0, ld_ext = 1'b0, ld_we = 1'b0;
  logic [15:0] ld_addr = '0;
  logic [7:0]  ld_data = '0;

  m20_boot_rom dut (.clk, .blk, .addr, .q, .ld_start, .ld_ext, .ld_we, .ld_addr, .ld_data);

  int errors = 0, checks = 0;

  // Image byte: socket tag in the high nibble of the H byte.
  function automatic logic [7:0] img(input int tag, input int a);
    return a[0] ? 8'(a >> 1) : 8'({tag[3:0], 4'(a >> 9)});
  endfunction
  function automatic logic [15:0] word(input int tag, input int w);
    return {img(tag, 2 * w), img(tag, 2 * w + 1)};
  endfunction

  task automatic load(input bit ext, input int n, input int tag0);
    @(posedge clk); ld_ext <= ext; ld_start <= 1'b1;
    @(posedge clk); ld_start <= 1'b0;
    for (int i = 0; i < n; i++) begin
      @(posedge clk); ld_we <= 1'b1; ld_addr <= 16'(i); ld_data <= img(tag0 + i / 16384, i % 16384);
    end
    @(posedge clk); ld_we <= 1'b0;
  endtask

  task automatic rd(input int b, input int w, input logic [15:0] exp, input string what);
    @(posedge clk); blk <= 3'(b); addr <= 13'(w);
    repeat (3) @(posedge clk);
    checks++;
    if (q !== exp) begin
      errors++;
      $display("FAIL %s: blk %0d word %04h got %04h expected %04h", what, b, w, q, exp);
    end
  endtask

  initial begin
    // 8 KB boot image: the upper 8 KB mirrors it.
    load(0, 8192, 1);
    rd(0, 16'h0000, word(1, 16'h0000), "boot 8K");
    rd(0, 16'h0FFF, word(1, 16'h0FFF), "boot 8K end");
    rd(0, 16'h1234, word(1, 16'h0234), "boot 8K mirror");
    for (int b = 1; b < 8; b++) rd(b, 16'h0010, 16'hFFFF, "no extension loaded");

    // 16 KB boot image.
    load(0, 16384, 2);
    rd(0, 16'h1234, word(2, 16'h1234), "boot 16K upper");
    rd(0, 16'h0234, word(2, 16'h0234), "boot 16K lower");

    // 40 KB extension: U55/U66 and U56/U67 full, U57/U68 8 KB (mirrored).
    load(1, 40960, 4);
    rd(4, 16'h0004, word(4, 16'h0004), "socket 4");
    rd(4, 16'h1FFF, word(4, 16'h1FFF), "socket 4 end");
    rd(5, 16'h1000, word(5, 16'h1000), "socket 5");
    rd(6, 16'h0123, word(6, 16'h0123), "socket 6");
    rd(6, 16'h1123, word(6, 16'h0123), "socket 6 mirror");
    rd(0, 16'h1234, word(2, 16'h1234), "boot untouched");
    for (int b = 1; b < 4; b++) rd(b, 16'h0010, 16'hFFFF, "unused U36 output");
    rd(7, 16'h0010, 16'hFFFF, "unused U36 O7");

    // 16 KB extension: sockets 5 and 6 empty again.
    load(1, 16384, 8);
    rd(4, 16'h1234, word(8, 16'h1234), "new socket 4");
    rd(5, 16'h1000, 16'hFFFF, "socket 5 emptied");
    rd(6, 16'h0123, 16'hFFFF, "socket 6 emptied");

    // 8 KB boot image again: A13 ignored again.
    load(0, 8192, 3);
    rd(0, 16'h1234, word(3, 16'h0234), "boot 8K mirror after 16K");

    if (errors == 0) $display("%0d checks\nPASS", checks);
    else $fatal(1, "%0d of %0d checks failed", errors, checks);
    $finish;
  end
endmodule
`default_nettype wire
