// Hard disk card: WD1000-compatible controller, register level, with two
// drives on disk image slots.
//
// Registers at 0x1C1 + 2n (controller A0-A2 on M20 A1-A3), D7-D0:
//   n  read            write
//   0  data            data
//   1  error           write precomp
//   2  sector count    sector count
//   3  sector          sector
//   4  cylinder low    cylinder low
//   5  cylinder high   cylinder high
//   6  SDH             SDH: [6:5] size (0 = 256 B), [4:3] drive, [2:0] head
//   7  status          command
// While busy every register reads as status.  The card answers only while
// an image is mounted.
//
// Drive: 6 heads x 33 sectors x 256 B, sectors numbered from 0; cylinders
// follow from the image size.  Sector LBA = (cyl * 6 + head) * 33 + sector,
// so each 512 B image block holds two sectors.  A sector write reads its
// block, replaces its half and writes the block back.  Format zero-fills
// the track's 33 sectors.  Seeks are instant.
`default_nettype none
module m20_hdc (
  input  logic             clk,
  input  logic             rst_n,
  // I/O bus
  input  logic [15:0]      io_addr,
  input  logic [15:0]      io_wdata,
  input  logic             io_rd,
  input  logic             io_wr,
  input  logic             io_rd_end,
  input  logic             io_wr_end,
  output logic             sel,          // this card decodes the access
  output logic [7:0]       rdata,
  output logic             intrq,
  // disk images
  input  logic [1:0]       d_mounted,    // pulse, with d_size and d_readonly
  input  logic             d_readonly,
  input  logic [63:0]      d_size,
  output logic [1:0][31:0] d_lba,
  output logic [1:0]       d_rd,
  output logic [1:0]       d_wr,
  input  logic [1:0]       d_ack,
  input  logic [8:0]       d_buff_addr,
  input  logic [7:0]       d_buff_dout,
  output logic [1:0][7:0]  d_buff_din,
  input  logic             d_buff_wr
);
  localparam logic [2:0]  HEADS = 3'd6;
  localparam logic [7:0]  SPT   = 8'd33;
  localparam logic [17:0] SPC   = 18'd198;     // sectors per cylinder
  localparam logic [17:0] SPT18 = 18'd33;

  localparam logic [7:0] ST_ERR = 8'h01, ST_DRQ = 8'h08, ST_SC = 8'h10,
                         ST_RDY = 8'h40, ST_BSY = 8'h80;
  localparam logic [7:0] ER_AC = 8'h04, ER_ID = 8'h10;

  // ---- media: told again after each machine reset -------------------------------------
  logic [1:0]  mnt_q;
  logic [1:0]  ro_q;
  logic [23:0] nsec_q [2];            // sectors in the image
  always_ff @(posedge clk)
    if (!rst_n) mnt_q <= 2'b00;
    else
      for (int i = 0; i < 2; i++)
        if (d_mounted[i]) mnt_q[i] <= d_size != 64'd0;
  always_ff @(posedge clk)
    for (int i = 0; i < 2; i++)
      if (d_mounted[i]) begin
        ro_q[i]   <= d_readonly;
        nsec_q[i] <= (d_size[63:32] != 32'd0) ? 24'hFFFFFF : d_size[31:8];
      end

  // ---- decode ----------------------------------------------------------------------------
  logic [2:0] rs;
  assign sel = (mnt_q != 2'b00) && io_addr[15:4] == 12'h01C;
  assign rs  = io_addr[3:1];

  // write data captured while /DS is low, committed at its rise
  logic [7:0] wd_q;
  always_ff @(posedge clk) if (io_wr && sel) wd_q <= io_wdata[7:0];

  logic host_rd, host_wr;
  assign host_rd = sel && io_rd_end;
  assign host_wr = sel && io_wr_end;

  // ---- task file -------------------------------------------------------------------------
  logic [7:0] err_q, precomp_q, scnt_q, sec_q, cyl_lo_q, sdh_q, cmd_q;
  logic [1:0] cyl_hi_q;
  logic       bsy_q, drq_q, sc_q, err_st_q;

  logic       drv;
  logic [2:0] head;
  logic       rdy;
  assign drv  = sdh_q[3];
  assign head = sdh_q[2:0];
  assign rdy  = sdh_q[4] == 1'b0 && mnt_q[drv];

  logic [7:0] status;
  assign status = (bsy_q ? ST_BSY : 8'h00) | (rdy ? ST_RDY : 8'h00) |
                  (sc_q ? ST_SC : 8'h00) | (drq_q ? ST_DRQ : 8'h00) | (err_st_q ? ST_ERR : 8'h00);

  // sector address of the task file
  logic [9:0]  cyl;
  logic [17:0] trk0;                  // first sector of the track
  logic [17:0] lba;
  logic        id_ok, trk_ok;
  assign cyl   = {cyl_hi_q, cyl_lo_q};
  assign trk0  = {8'd0, cyl} * SPC + {15'd0, head} * SPT18;
  assign lba   = trk0 + {10'd0, sec_q};
  assign trk_ok = sdh_q[6:5] == 2'b00 && head < HEADS && {6'd0, trk0} < nsec_q[drv];
  assign id_ok  = trk_ok && sec_q < SPT && {6'd0, lba} < nsec_q[drv];

  // ---- sector buffer: one image block ----------------------------------------------------
  logic [8:0] b_addr;
  logic [7:0] b_d, b_q;
  logic       b_we;
  (* ramstyle = "M10K, no_rw_check" *) logic [7:0] sbuf [0:511];
  always_ff @(posedge clk) begin
    if (b_we) sbuf[b_addr] <= b_d;
    b_q <= sbuf[b_addr];
  end

  // ---- command engine --------------------------------------------------------------------
  typedef enum logic [2:0] {E_IDLE, E_DATA, E_RD, E_RDX, E_WR, E_WRX, E_NEXT} eng_e;
  eng_e        e_st;
  logic [3:0]  op_q;                  // command bits 7:4
  logic        half_q;                // sector's half of its block
  logic [7:0]  ptr_q;                 // host byte within the sector
  logic [16:0] blk_q, blk_end_q;      // block being transferred, last block
  logic [17:0] trk0_q;
  logic        jdrv_q;
  logic [1:0]  keep_q;                // per half: store the image byte (else hold / zero)
  logic [1:0]  zero_q;                // per half: store zero

  localparam logic [3:0] OP_RESTORE = 4'd1, OP_READ = 4'd2, OP_WRITE = 4'd3,
                         OP_FORMAT  = 4'd5, OP_SEEK = 4'd7;

  // halves of block b inside the track starting at sector t
  function automatic logic [1:0] in_trk(input logic [16:0] b, input logic [17:0] t);
    logic [17:0] s0, s1;
    s0 = {b, 1'b0};
    s1 = {b, 1'b1};
    return {s1 >= t && s1 < t + SPT18, s0 >= t && s0 < t + SPT18};
  endfunction

  logic job_rd, job_wr;
  assign job_rd = e_st == E_RD || e_st == E_RDX;
  assign job_wr = e_st == E_WR || e_st == E_WRX;

  always_comb begin
    for (int i = 0; i < 2; i++) begin
      d_lba[i]      = {15'd0, blk_q};
      d_rd[i]       = e_st == E_RD && jdrv_q == 1'(i);
      d_wr[i]       = e_st == E_WR && jdrv_q == 1'(i);
      d_buff_din[i] = b_q;
    end
    b_addr = (job_rd || job_wr) ? d_buff_addr : {half_q, ptr_q};
    b_d    = wd_q;
    b_we   = 1'b0;
    if (e_st == E_RDX && d_buff_wr && d_ack[jdrv_q]) begin
      b_we = keep_q[d_buff_addr[8]] || zero_q[d_buff_addr[8]];
      b_d  = zero_q[d_buff_addr[8]] ? 8'h00 : d_buff_dout;
    end else if (e_st == E_DATA && host_wr && rs == 3'd0 && drq_q) begin
      b_we = 1'b1;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      e_st <= E_IDLE;
      err_q <= 8'h00; precomp_q <= 8'h00; scnt_q <= 8'h00; sec_q <= 8'h00;
      cyl_lo_q <= 8'h00; cyl_hi_q <= 2'd0; sdh_q <= 8'h20; cmd_q <= 8'h00;
      bsy_q <= 1'b0; drq_q <= 1'b0; sc_q <= 1'b1; err_st_q <= 1'b0; intrq <= 1'b0;
      op_q <= 4'd0; half_q <= 1'b0; ptr_q <= 8'd0; blk_q <= '0; blk_end_q <= '0;
      trk0_q <= '0; jdrv_q <= 1'b0; keep_q <= 2'b00; zero_q <= 2'b00;
    end else begin
      // ---- register reads with side effects
      if (host_rd && !bsy_q) begin
        unique case (rs)
          3'd0: if (drq_q && e_st == E_IDLE) begin
            ptr_q <= ptr_q + 8'd1;
            if (ptr_q == 8'hFF) drq_q <= 1'b0;
          end
          3'd4: begin intrq <= 1'b0; if (e_st == E_IDLE) drq_q <= 1'b0; end
          3'd7: intrq <= 1'b0;
          default: ;
        endcase
      end
      if (host_rd && bsy_q) intrq <= 1'b0;

      // ---- register writes
      if (host_wr) begin
        unique case (rs)
          3'd0: if (drq_q && e_st == E_DATA) begin
            ptr_q <= ptr_q + 8'd1;
            if (ptr_q == 8'hFF) begin            // sector buffer full
              drq_q <= 1'b0;
              bsy_q <= 1'b1;
              if (op_q == OP_WRITE ? !id_ok : !trk_ok) begin
                err_q <= ER_ID; err_st_q <= 1'b1; bsy_q <= 1'b0; intrq <= 1'b1;
                e_st  <= E_IDLE;
              end else if (ro_q[jdrv_q]) begin
                err_q <= ER_AC; err_st_q <= 1'b1; bsy_q <= 1'b0; intrq <= 1'b1;
                e_st  <= E_IDLE;
              end else if (op_q == OP_WRITE) begin
                keep_q <= half_q ? 2'b01 : 2'b10;
                zero_q <= 2'b00;
                e_st   <= E_RD;
              end else begin                     // format: blocks of the track
                blk_q     <= trk0_q[17:1];
                blk_end_q <= 17'((trk0_q + SPT18 - 18'd1) >> 1);
                keep_q    <= ~in_trk(trk0_q[17:1], trk0_q);
                zero_q    <=  in_trk(trk0_q[17:1], trk0_q);
                e_st      <= E_RD;
              end
            end
          end
          3'd1: if (!bsy_q) precomp_q <= wd_q;
          3'd2: if (!bsy_q) scnt_q    <= wd_q;
          3'd3: if (!bsy_q) sec_q     <= wd_q;
          3'd4: if (!bsy_q) cyl_lo_q  <= wd_q;
          3'd5: if (!bsy_q) cyl_hi_q  <= wd_q[1:0];
          3'd6: if (!bsy_q) sdh_q     <= wd_q;
          3'd7: if (!bsy_q) begin
            cmd_q    <= wd_q;
            op_q     <= wd_q[7:4];
            intrq    <= 1'b0;
            err_q    <= 8'h00;
            err_st_q <= 1'b0;
            drq_q    <= 1'b0;
            e_st     <= E_IDLE;
            if (!rdy) begin
              err_q <= ER_AC; err_st_q <= 1'b1; intrq <= 1'b1;
            end else begin
              jdrv_q <= drv;
              half_q <= lba[0];
              ptr_q  <= 8'd0;
              trk0_q <= trk0;
              blk_q  <= 17'(lba >> 1);
              unique case (wd_q[7:4])
                OP_RESTORE, OP_SEEK: begin sc_q <= 1'b1; intrq <= 1'b1; end
                OP_READ: if (!id_ok) begin
                  err_q <= ER_ID; err_st_q <= 1'b1; intrq <= 1'b1;
                end else begin
                  bsy_q  <= 1'b1;
                  keep_q <= 2'b11;
                  zero_q <= 2'b00;
                  e_st   <= E_RD;
                end
                OP_WRITE, OP_FORMAT: begin
                  half_q <= (wd_q[7:4] == OP_WRITE) && lba[0];
                  drq_q  <= 1'b1;
                  e_st   <= E_DATA;
                end
                default: begin err_q <= ER_AC; err_st_q <= 1'b1; intrq <= 1'b1; end
              endcase
            end
          end
          default: ;
        endcase
      end

      // ---- image transfers
      unique case (e_st)
        E_RD:  if (d_ack[jdrv_q]) e_st <= E_RDX;
        E_RDX: if (!d_ack[jdrv_q]) begin
          if (op_q == OP_READ) begin
            bsy_q <= 1'b0;
            drq_q <= 1'b1;
            intrq <= 1'b1;
            e_st  <= E_IDLE;
          end else begin
            e_st <= E_WR;
          end
        end
        E_WR:  if (d_ack[jdrv_q]) e_st <= E_WRX;
        E_WRX: if (!d_ack[jdrv_q]) e_st <= E_NEXT;
        E_NEXT: if (op_q == OP_FORMAT && blk_q != blk_end_q) begin
          blk_q  <= blk_q + 17'd1;
          keep_q <= ~in_trk(blk_q + 17'd1, trk0_q);
          zero_q <=  in_trk(blk_q + 17'd1, trk0_q);
          e_st   <= E_RD;
        end else begin
          if (op_q == OP_FORMAT) scnt_q <= 8'h00;
          bsy_q <= 1'b0;
          intrq <= 1'b1;
          e_st  <= E_IDLE;
        end
        default: ;
      endcase
    end
  end

  // ---- read data -------------------------------------------------------------------------
  always_comb begin
    rdata = status;
    if (!bsy_q) begin
      unique case (rs)
        3'd0: rdata = b_q;
        3'd1: rdata = err_q;
        3'd2: rdata = scnt_q;
        3'd3: rdata = sec_q;
        3'd4: rdata = cyl_lo_q;
        3'd5: rdata = {6'd0, cyl_hi_q};
        3'd6: rdata = sdh_q;
        default: rdata = status;
      endcase
    end
  end

  logic unused_ok;
  assign unused_ok = &{1'b0, io_addr[0], io_wdata[15:8], precomp_q, cmd_q, io_rd};
endmodule
`default_nettype wire
