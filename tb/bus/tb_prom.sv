// U44 mapping PROM (m20_prom) against the documented mapping table:
//   1. hand-transcribed rows, decoded (device, offset) form, driven on the
//      named pins (A14, A15, SN, ST2, jumpers);
//   2. every table entry (prom_vec.txt: address, expected byte);
//   3. code 4 (undocumented) reads as code 5.
`default_nettype none
module tb_prom;
  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic a14, a15, st2;
  logic [3:0] sn;
  logic [2:0] code;
  logic [7:0] q;
  m20_prom #(.INIT_FILE("../../rtl/bus/m20_prom.hex")) dut (
    .clk(clk), .a14(a14), .a15(a15), .sn(sn), .st2(st2),
    .j_32_128(code[1]), .j_bw(code[2]), .j_col48(code[0]), .q(q)
  );

  int errors = 0, checks = 0;

  task automatic look(input logic [2:0] c, input logic [3:0] s, input logic [15:0] off,
                      input logic i, output logic [7:0] r);
    code = c; sn = s; a15 = off[15]; a14 = off[14]; st2 = i;
    @(posedge clk); #1 r = q;
  endtask

  // kind: "DRAMn", "ROM0", "SRAM0", "None"; off = byte offset in the device
  task automatic row(input logic [2:0] c, input logic [3:0] s, input logic [15:0] off,
                     input string sp, input string kind, input int doff);
    logic [7:0] r;
    string got;
    look(c, s, off, sp == "I", r);
    checks++;
    if (!r[5])                          got = $sformatf("DRAM%0d %0h", r[4:3], int'(r[2:0]) << 14);
    else if (!r[7] && r[4:3] == 2'd0)   got = $sformatf("ROM0 %0h", int'(r[2:0]) << 14);
    else if (!r[6])                     got = "SRAM0 0";
    else if (r[7:5] == 3'b111)          got = "None 0";
    else                                got = $sformatf("?%02h", r);
    if (got != $sformatf("%s %0h", kind, doff)) begin
      $display("FAIL code %0d <%h>%04h %s: %s, Appendix A %s %0h", c, s, off, sp, got, kind, doff);
      errors++;
    end
  endtask

  initial begin
    int fd, a, v;
    string line;
    logic [7:0] r4, r5;
    // No Expansion (5)
    row(5, 0, 16'h0000, "D", "DRAM0", 'h4000);   row(5, 0, 16'h4000, "D", "None", 0);
    row(5, 0, 16'h4000, "I", "DRAM0", 'h8000);   row(5, 1, 16'hC000, "D", "DRAM0", 'h10000);
    row(5, 1, 16'hC000, "I", "None", 0);         row(5, 3, 16'h0000, "I", "DRAM0", 'h0000);
    row(5, 4, 16'h0000, "D", "ROM0", 'h0000);    row(5, 5, 16'h0000, "I", "ROM0", 'h10000);
    row(5, 5, 16'h0000, "D", "DRAM0", 'h8000);   row(5, 5, 16'hC000, "D", "SRAM0", 0);
    row(5, 6, 16'hC000, "I", "None", 0);         row(5, 7, 16'hC000, "D", "ROM0", 'h18000);
    row(5, 8, 16'h0000, "D", "DRAM0", 'h18000);  row(5, 8, 16'h0000, "I", "DRAM0", 'h8000);
    row(5, 9, 16'h4000, "D", "DRAM0", 'h1C000);  row(5, 4'hF, 16'hC000, "D", "None", 0);
    // 8 Colors 128K (0)
    row(0, 0, 16'hC000, "D", "DRAM3", 'h0000);   row(0, 0, 16'hC000, "I", "DRAM0", 'h10000);
    row(0, 3, 16'h4000, "D", "DRAM1", 'h0000);   row(0, 5, 16'hC000, "D", "None", 0);
    row(0, 5, 16'hC000, "I", "SRAM0", 0);        row(0, 7, 16'hC000, "D", "DRAM3", 'h4000);
    row(0, 4'hB, 16'h8000, "D", "DRAM2", 'h4000); row(0, 4'hF, 16'hC000, "I", "DRAM3", 'h8000);
    row(0, 1, 16'hC000, "I", "None", 0);         row(0, 4'h8, 16'h8000, "D", "DRAM1", 'h10000);
    // B/W 128K (6)
    row(6, 4, 16'h4000, "D", "DRAM3", 'h0000);   row(6, 4, 16'h4000, "I", "None", 0);
    row(6, 0, 16'h4000, "D", "DRAM1", 'h4000);   row(6, 4'hF, 16'hC000, "D", "DRAM3", 'h0000);
    row(6, 3, 16'h4000, "D", "None", 0);         row(6, 4'hB, 16'hC000, "I", "DRAM2", 'h0000);
    // B/W 32K (7)
    row(7, 4'hC, 16'h0000, "D", "DRAM3", 'h4000); row(7, 4'hC, 16'h0000, "I", "None", 0);
    row(7, 8, 16'hC000, "D", "DRAM3", 'h0000);   row(7, 8, 16'hC000, "I", "DRAM2", 'h0000);
    row(7, 4, 16'hC000, "I", "ROM0", 'h18000);   row(7, 4, 16'hC000, "D", "None", 0);
    // 4 Colors 32K (3), 8 Colors 32K (2), 4 Colors 128K (1)
    row(3, 8, 16'h8000, "D", "DRAM3", 'h0000);   row(3, 8, 16'h8000, "I", "DRAM2", 'h0000);
    row(3, 3, 16'h8000, "D", "None", 0);         row(2, 8, 16'h8000, "D", "DRAM3", 'h4000);
    row(2, 8, 16'hC000, "D", "None", 0);         row(2, 8, 16'hC000, "I", "DRAM3", 'h0000);
    row(1, 7, 16'hC000, "D", "DRAM3", 'h4000);   row(1, 7, 16'hC000, "I", "ROM0", 'h18000);
    row(1, 4'hF, 16'h8000, "D", "DRAM3", 'h0000); row(1, 3, 16'h8000, "D", "None", 0);
    $display("tb_prom: %0d hand-transcribed rows", checks);

    fd = $fopen("prom_vec.txt", "r");
    if (fd == 0) $fatal(1, "cannot open obj_dir/prom_vec.txt");
    while ($fgets(line, fd)) if ($sscanf(line, "%h %h", a, v) == 2) begin
      logic [7:0] r;
      look({a[8], a[7], a[9]}, {a[6], a[4:2]}, {a[1], a[0], 14'h0}, a[5], r);
      checks++;
      if (r != 8'(v)) begin
        $display("FAIL PROM %03h: %02h, Appendix A %02h", a, r, v);
        errors++;
      end
    end
    $fclose(fd);

    for (int s = 0; s < 16; s++) for (int o = 0; o < 4; o++) for (int i = 0; i < 2; i++) begin
      look(3'd4, 4'(s), {2'(o), 14'h0}, 1'(i), r4);
      look(3'd5, 4'(s), {2'(o), 14'h0}, 1'(i), r5);
      checks++;
      if (r4 != r5) begin $display("FAIL code 4 <%h>%04h: %02h vs code 5 %02h", s, o << 14, r4, r5); errors++; end
    end

    $display("tb_prom: %0d checks", checks);
    if (errors != 0) $fatal(1, "tb_prom: %0d errors", errors);
    $display("PASS");
    $finish;
  end
endmodule
`default_nettype wire
