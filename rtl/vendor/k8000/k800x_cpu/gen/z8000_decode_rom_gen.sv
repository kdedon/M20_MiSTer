// DERIVED FILE, but a COMMITTED SOURCE of k8000: check it in, review its
// diffs, and build from it. Nothing in k8000's lint/build/test reads any
// other repo.
//
// Do not hand-edit: it is emitted by cmd/decoderom from the Z8000 Go golden
// model, and 'make refresh-rtl' (maintainers only, needs that model) will
// overwrite it. What proves it correct HERE is tb_decode replaying the
// committed vectors/k800x_cpu/decode/decode.vec -- no external repo needed.
//
// z8000_decode_rom_gen: reference decode ROM, f(w0[15:0], w1[3:0]) -> ctrl.
// Only bits 3:0 of the second word ever influence the control word (the
// 3A/3B/BA/BB/1C/5C sub-decoders); everything else is a function of w0.
// Structure mirrors the Go ROM: case on the high byte, then (only where the
// Go entry is a sub-decoder) on the low byte and the w1 nibble. Synthesis
// minimizes the constant tables; the tb (tb_decode) checks this module
// against vectors/decode/decode.vec, and it is the golden reference for
// any hand-structured decoder you write in rtl/z8000_decode.sv.

module z8000_decode_rom_gen
  import z8000_ctrl_pkg::*;
(
  input  logic [15:0] w0,      // instruction first word
  input  logic [3:0]  w1_lo,   // second word bits 3:0 (0 if not yet fetched)
  output ctrl_word_t  ctrl
);

  localparam int W = CTRL_W;

  always_comb begin
    ctrl = ctrl_word_t'(W'(0));
    case (w0[15:8])
      8'h00: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h100108000000000000);
          default:
            ctrl = ctrl_word_t'(69'h10010c002000000000);
        endcase
      end
      8'h01: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h100208000000000000);
          default:
            ctrl = ctrl_word_t'(69'h10020c002000000000);
        endcase
      end
      8'h02: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h100908000000000000);
          default:
            ctrl = ctrl_word_t'(69'h10090c002000000000);
        endcase
      end
      8'h03: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h100a08000000000000);
          default:
            ctrl = ctrl_word_t'(69'h100a0c002000000000);
        endcase
      end
      8'h04: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h101508000000000000);
          default:
            ctrl = ctrl_word_t'(69'h10150c002000000000);
        endcase
      end
      8'h05: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h101608000000000000);
          default:
            ctrl = ctrl_word_t'(69'h10160c002000000000);
        endcase
      end
      8'h06: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h101108000000000000);
          default:
            ctrl = ctrl_word_t'(69'h10110c002000000000);
        endcase
      end
      8'h07: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h101208000000000000);
          default:
            ctrl = ctrl_word_t'(69'h10120c002000000000);
        endcase
      end
      8'h08: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h101908000000000000);
          default:
            ctrl = ctrl_word_t'(69'h10190c002000000000);
        endcase
      end
      8'h09: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h101a08000000000000);
          default:
            ctrl = ctrl_word_t'(69'h101a0c002000000000);
        endcase
      end
      8'h0A: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h102908400000000000);
          default:
            ctrl = ctrl_word_t'(69'h10290c402000000000);
        endcase
      end
      8'h0B: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h102a08400000000000);
          default:
            ctrl = ctrl_word_t'(69'h102a0c402000000000);
        endcase
      end
      8'h0C: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(69'h101d0cc02800000000);
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(69'h10290c842000000000);
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(69'h10210cc02800000000);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(69'h10250c802000000000);
          8'h05, 8'h15, 8'h25, 8'h35, 8'h45, 8'h55, 8'h65, 8'h75, 8'h85, 8'h95, 8'hA5, 8'hB5, 
          8'hC5, 8'hD5, 8'hE5, 8'hF5:
            ctrl = ctrl_word_t'(69'h105d08c00800000000);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(69'h106d0cc02800000000);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(69'h105d24c00800000000);
          default:
            ctrl = ctrl_word_t'(69'h000000000000000000);
        endcase
      end
      8'h0D: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(69'h101e0cc02800000000);
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(69'h102a0c842000000000);
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(69'h10220cc02800000000);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(69'h10260c802000000000);
          8'h05, 8'h15, 8'h25, 8'h35, 8'h45, 8'h55, 8'h65, 8'h75, 8'h85, 8'h95, 8'hA5, 8'hB5, 
          8'hC5, 8'hD5, 8'hE5, 8'hF5:
            ctrl = ctrl_word_t'(69'h105e08c00800000000);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(69'h106e0cc02800000000);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(69'h105e24c00800000000);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(69'h118000000000008000);
          default:
            ctrl = ctrl_word_t'(69'h000000000000000000);
        endcase
      end
      8'h0E: ctrl = ctrl_word_t'(69'h1d800c000000000001);
      8'h0F: ctrl = ctrl_word_t'(69'h1d800c000000000001);
      8'h10: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h102b08400000000000);
          default:
            ctrl = ctrl_word_t'(69'h102b0c402000000000);
        endcase
      end
      8'h11: ctrl = ctrl_word_t'(69'h11800c000000006000);
      8'h12: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h100b08000000000000);
          default:
            ctrl = ctrl_word_t'(69'h100b0c002000000000);
        endcase
      end
      8'h13: ctrl = ctrl_word_t'(69'h11800c000000004000);
      8'h14: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h105f08000000000000);
          default:
            ctrl = ctrl_word_t'(69'h105f0c002000000000);
        endcase
      end
      8'h15: ctrl = ctrl_word_t'(69'h118000c00000007000);
      8'h16: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h100308000000000000);
          default:
            ctrl = ctrl_word_t'(69'h10030c002000000000);
        endcase
      end
      8'h17: ctrl = ctrl_word_t'(69'h118000c00000005000);
      8'h18: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h1a0308000000000000);
          default:
            ctrl = ctrl_word_t'(69'h1a030c002000000000);
        endcase
      end
      8'h19: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h1a0208000000000000);
          default:
            ctrl = ctrl_word_t'(69'h1a020c002000000000);
        endcase
      end
      8'h1A: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h1a8308000000000000);
          default:
            ctrl = ctrl_word_t'(69'h1a830c002000000000);
        endcase
      end
      8'h1B: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h1a8208000000000000);
          default:
            ctrl = ctrl_word_t'(69'h1a820c002000000000);
        endcase
      end
      8'h1C: begin
        case (w0[7:0])
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(69'h19000c000000000000);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(69'h10270c802000000000);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(69'h19000c000000000080);
          default:
            ctrl = ctrl_word_t'(69'h000000000000000000);
        endcase
      end
      8'h1D: ctrl = ctrl_word_t'(69'h105f04c00800000000);
      8'h1E: ctrl = ctrl_word_t'(69'h120000000000000200);
      8'h1F: ctrl = ctrl_word_t'(69'h120000000000000600);
      8'h20: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h105d08000000000000);
          default:
            ctrl = ctrl_word_t'(69'h105d0c002000000000);
        endcase
      end
      8'h21: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h105e08000000000000);
          default:
            ctrl = ctrl_word_t'(69'h105e0c002000000000);
        endcase
      end
      8'h22: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h14e900000000000000);
          default:
            ctrl = ctrl_word_t'(69'h10690cdc2800000000);
        endcase
      end
      8'h23: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h14ea00000000000000);
          default:
            ctrl = ctrl_word_t'(69'h106a0cdc2800000000);
        endcase
      end
      8'h24: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h14e500000000000000);
          default:
            ctrl = ctrl_word_t'(69'h10650cdc2800000000);
        endcase
      end
      8'h25: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h14e600000000000000);
          default:
            ctrl = ctrl_word_t'(69'h10660cdc2800000000);
        endcase
      end
      8'h26: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h14e100000000000000);
          default:
            ctrl = ctrl_word_t'(69'h10610c9c2800000000);
        endcase
      end
      8'h27: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h14e200000000000000);
          default:
            ctrl = ctrl_word_t'(69'h10620c9c2800000000);
        endcase
      end
      8'h28: ctrl = ctrl_word_t'(69'h102d0cde2800000000);
      8'h29: ctrl = ctrl_word_t'(69'h102e0cde2800000000);
      8'h2A: ctrl = ctrl_word_t'(69'h10310cde2800000000);
      8'h2B: ctrl = ctrl_word_t'(69'h10320cde2800000000);
      8'h2C: ctrl = ctrl_word_t'(69'h13810c000000000000);
      8'h2D: ctrl = ctrl_word_t'(69'h13820c000000000000);
      8'h2E: ctrl = ctrl_word_t'(69'h105d04c00800000000);
      8'h2F: ctrl = ctrl_word_t'(69'h105e04c00800000000);
      8'h30: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h105d2c000000000000);
          default:
            ctrl = ctrl_word_t'(69'h105d30002000000000);
        endcase
      end
      8'h31: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h105e2c000000000000);
          default:
            ctrl = ctrl_word_t'(69'h105e30002000000000);
        endcase
      end
      8'h32: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h105d05800000000000);
          default:
            ctrl = ctrl_word_t'(69'h105d05c00800000000);
        endcase
      end
      8'h33: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h105e05800000000000);
          default:
            ctrl = ctrl_word_t'(69'h105e05c00800000000);
        endcase
      end
      8'h34: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h15002c000000000000);
          default:
            ctrl = ctrl_word_t'(69'h150030002000000000);
        endcase
      end
      8'h35: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h105f2c000000000000);
          default:
            ctrl = ctrl_word_t'(69'h105f30002000000000);
        endcase
      end
      8'h36: ctrl = ctrl_word_t'(69'h000000000000000000);
      8'h37: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h105f05800000000000);
          default:
            ctrl = ctrl_word_t'(69'h105f05c00800000000);
        endcase
      end
      8'h38: ctrl = ctrl_word_t'(69'h000000000000000000);
      8'h39: ctrl = ctrl_word_t'(69'h1b008c000000000000);
      8'h3A: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(69'h188180000000000000);
            default: ctrl = ctrl_word_t'(69'h188180000000000010);
          endcase
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(69'h188180000000000040);
            default: ctrl = ctrl_word_t'(69'h188180000000000050);
          endcase
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(69'h188180000000000080);
            default: ctrl = ctrl_word_t'(69'h188180000000000090);
          endcase
          8'h03, 8'h13, 8'h23, 8'h33, 8'h43, 8'h53, 8'h63, 8'h73, 8'h83, 8'h93, 8'hA3, 8'hB3, 
          8'hC3, 8'hD3, 8'hE3, 8'hF3:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(69'h1881800000000000c0);
            default: ctrl = ctrl_word_t'(69'h1881800000000000d0);
          endcase
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(69'h158180000000000000);
          8'h05, 8'h15, 8'h25, 8'h35, 8'h45, 8'h55, 8'h65, 8'h75, 8'h85, 8'h95, 8'hA5, 8'hB5, 
          8'hC5, 8'hD5, 8'hE5, 8'hF5:
            ctrl = ctrl_word_t'(69'h158180000000000040);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(69'h158180000000000080);
          8'h07, 8'h17, 8'h27, 8'h37, 8'h47, 8'h57, 8'h67, 8'h77, 8'h87, 8'h97, 8'hA7, 8'hB7, 
          8'hC7, 8'hD7, 8'hE7, 8'hF7:
            ctrl = ctrl_word_t'(69'h1581800000000000c0);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(69'h188180000000000020);
            default: ctrl = ctrl_word_t'(69'h188180000000000030);
          endcase
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(69'h188180000000000060);
            default: ctrl = ctrl_word_t'(69'h188180000000000070);
          endcase
          8'h0A, 8'h1A, 8'h2A, 8'h3A, 8'h4A, 8'h5A, 8'h6A, 8'h7A, 8'h8A, 8'h9A, 8'hAA, 8'hBA, 
          8'hCA, 8'hDA, 8'hEA, 8'hFA:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(69'h1881800000000000a0);
            default: ctrl = ctrl_word_t'(69'h1881800000000000b0);
          endcase
          8'h0B, 8'h1B, 8'h2B, 8'h3B, 8'h4B, 8'h5B, 8'h6B, 8'h7B, 8'h8B, 8'h9B, 8'hAB, 8'hBB, 
          8'hCB, 8'hDB, 8'hEB, 8'hFB:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(69'h1881800000000000e0);
            default: ctrl = ctrl_word_t'(69'h1881800000000000f0);
          endcase
          default:
            ctrl = ctrl_word_t'(69'h000000000000000000);
        endcase
      end
      8'h3B: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(69'h188280000000000000);
            default: ctrl = ctrl_word_t'(69'h188280000000000010);
          endcase
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(69'h188280000000000040);
            default: ctrl = ctrl_word_t'(69'h188280000000000050);
          endcase
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(69'h188280000000000080);
            default: ctrl = ctrl_word_t'(69'h188280000000000090);
          endcase
          8'h03, 8'h13, 8'h23, 8'h33, 8'h43, 8'h53, 8'h63, 8'h73, 8'h83, 8'h93, 8'hA3, 8'hB3, 
          8'hC3, 8'hD3, 8'hE3, 8'hF3:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(69'h1882800000000000c0);
            default: ctrl = ctrl_word_t'(69'h1882800000000000d0);
          endcase
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(69'h158280000000000000);
          8'h05, 8'h15, 8'h25, 8'h35, 8'h45, 8'h55, 8'h65, 8'h75, 8'h85, 8'h95, 8'hA5, 8'hB5, 
          8'hC5, 8'hD5, 8'hE5, 8'hF5:
            ctrl = ctrl_word_t'(69'h158280000000000040);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(69'h158280000000000080);
          8'h07, 8'h17, 8'h27, 8'h37, 8'h47, 8'h57, 8'h67, 8'h77, 8'h87, 8'h97, 8'hA7, 8'hB7, 
          8'hC7, 8'hD7, 8'hE7, 8'hF7:
            ctrl = ctrl_word_t'(69'h1582800000000000c0);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(69'h188280000000000020);
            default: ctrl = ctrl_word_t'(69'h188280000000000030);
          endcase
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(69'h188280000000000060);
            default: ctrl = ctrl_word_t'(69'h188280000000000070);
          endcase
          8'h0A, 8'h1A, 8'h2A, 8'h3A, 8'h4A, 8'h5A, 8'h6A, 8'h7A, 8'h8A, 8'h9A, 8'hAA, 8'hBA, 
          8'hCA, 8'hDA, 8'hEA, 8'hFA:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(69'h1882800000000000a0);
            default: ctrl = ctrl_word_t'(69'h1882800000000000b0);
          endcase
          8'h0B, 8'h1B, 8'h2B, 8'h3B, 8'h4B, 8'h5B, 8'h6B, 8'h7B, 8'h8B, 8'h9B, 8'hAB, 8'hBB, 
          8'hCB, 8'hDB, 8'hEB, 8'hFB:
            case (w1_lo)
            4'h8: ctrl = ctrl_word_t'(69'h1882800000000000e0);
            default: ctrl = ctrl_word_t'(69'h1882800000000000f0);
          endcase
          default:
            ctrl = ctrl_word_t'(69'h000000000000000000);
        endcase
      end
      8'h3C: ctrl = ctrl_word_t'(69'h15818c000000000000);
      8'h3D: ctrl = ctrl_word_t'(69'h15828c000000000000);
      8'h3E: ctrl = ctrl_word_t'(69'h15818c000000000080);
      8'h3F: ctrl = ctrl_word_t'(69'h15828c000000000080);
      8'h40: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h100110000000000000);
          default:
            ctrl = ctrl_word_t'(69'h100114002000000000);
        endcase
      end
      8'h41: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h100210000000000000);
          default:
            ctrl = ctrl_word_t'(69'h100214002000000000);
        endcase
      end
      8'h42: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h100910000000000000);
          default:
            ctrl = ctrl_word_t'(69'h100914002000000000);
        endcase
      end
      8'h43: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h100a10000000000000);
          default:
            ctrl = ctrl_word_t'(69'h100a14002000000000);
        endcase
      end
      8'h44: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h101510000000000000);
          default:
            ctrl = ctrl_word_t'(69'h101514002000000000);
        endcase
      end
      8'h45: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h101610000000000000);
          default:
            ctrl = ctrl_word_t'(69'h101614002000000000);
        endcase
      end
      8'h46: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h101110000000000000);
          default:
            ctrl = ctrl_word_t'(69'h101114002000000000);
        endcase
      end
      8'h47: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h101210000000000000);
          default:
            ctrl = ctrl_word_t'(69'h101214002000000000);
        endcase
      end
      8'h48: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h101910000000000000);
          default:
            ctrl = ctrl_word_t'(69'h101914002000000000);
        endcase
      end
      8'h49: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h101a10000000000000);
          default:
            ctrl = ctrl_word_t'(69'h101a14002000000000);
        endcase
      end
      8'h4A: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h102910400000000000);
          default:
            ctrl = ctrl_word_t'(69'h102914402000000000);
        endcase
      end
      8'h4B: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h102a10400000000000);
          default:
            ctrl = ctrl_word_t'(69'h102a14402000000000);
        endcase
      end
      8'h4C: begin
        case (w0[7:0])
          8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 8'hC0, 
          8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(69'h101d15402800000000);
          8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 8'hC1, 
          8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(69'h102914942000000000);
          8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 8'hC2, 
          8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(69'h102115402800000000);
          8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 8'hC4, 
          8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(69'h102514802000000000);
          8'h15, 8'h25, 8'h35, 8'h45, 8'h55, 8'h65, 8'h75, 8'h85, 8'h95, 8'hA5, 8'hB5, 8'hC5, 
          8'hD5, 8'hE5, 8'hF5:
            ctrl = ctrl_word_t'(69'h105d29400800000000);
          8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 8'hC6, 
          8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(69'h106d15402800000000);
          8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 8'hC8, 
          8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(69'h105d25400800000000);
          8'h00:
            ctrl = ctrl_word_t'(69'h101d11002800000000);
          8'h01:
            ctrl = ctrl_word_t'(69'h102910942000000000);
          8'h02:
            ctrl = ctrl_word_t'(69'h102111002800000000);
          8'h04:
            ctrl = ctrl_word_t'(69'h102510802000000000);
          8'h05:
            ctrl = ctrl_word_t'(69'h105d29000800000000);
          8'h06:
            ctrl = ctrl_word_t'(69'h106d11002800000000);
          8'h08:
            ctrl = ctrl_word_t'(69'h105d25000800000000);
          default:
            ctrl = ctrl_word_t'(69'h000000000000000000);
        endcase
      end
      8'h4D: begin
        case (w0[7:0])
          8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 8'hC0, 
          8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(69'h101e15402800000000);
          8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 8'hC1, 
          8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(69'h102a14942000000000);
          8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 8'hC2, 
          8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(69'h102215402800000000);
          8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 8'hC4, 
          8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(69'h102614802000000000);
          8'h15, 8'h25, 8'h35, 8'h45, 8'h55, 8'h65, 8'h75, 8'h85, 8'h95, 8'hA5, 8'hB5, 8'hC5, 
          8'hD5, 8'hE5, 8'hF5:
            ctrl = ctrl_word_t'(69'h105e29400800000000);
          8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 8'hC6, 
          8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(69'h106e15402800000000);
          8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 8'hC8, 
          8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(69'h105e25400800000000);
          8'h00:
            ctrl = ctrl_word_t'(69'h101e11002800000000);
          8'h01:
            ctrl = ctrl_word_t'(69'h102a10942000000000);
          8'h02:
            ctrl = ctrl_word_t'(69'h102211002800000000);
          8'h04:
            ctrl = ctrl_word_t'(69'h102610802000000000);
          8'h05:
            ctrl = ctrl_word_t'(69'h105e29000800000000);
          8'h06:
            ctrl = ctrl_word_t'(69'h106e11002800000000);
          8'h08:
            ctrl = ctrl_word_t'(69'h105e25000800000000);
          default:
            ctrl = ctrl_word_t'(69'h000000000000000000);
        endcase
      end
      8'h4E: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h1d8010000000000001);
          default:
            ctrl = ctrl_word_t'(69'h1d8014000000000001);
        endcase
      end
      8'h4F: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h1d8010000000000001);
          default:
            ctrl = ctrl_word_t'(69'h1d8014000000000001);
        endcase
      end
      8'h50: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h102b10400000000000);
          default:
            ctrl = ctrl_word_t'(69'h102b14402000000000);
        endcase
      end
      8'h51: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(69'h118010000000006000);
          default:
            ctrl = ctrl_word_t'(69'h118014000000006000);
        endcase
      end
      8'h52: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h100b10000000000000);
          default:
            ctrl = ctrl_word_t'(69'h100b14002000000000);
        endcase
      end
      8'h53: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(69'h118010000000004000);
          default:
            ctrl = ctrl_word_t'(69'h118014000000004000);
        endcase
      end
      8'h54: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h105f10000000000000);
          default:
            ctrl = ctrl_word_t'(69'h105f14002000000000);
        endcase
      end
      8'h55: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(69'h118001000000007000);
          default:
            ctrl = ctrl_word_t'(69'h118001400000007000);
        endcase
      end
      8'h56: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h100310000000000000);
          default:
            ctrl = ctrl_word_t'(69'h100314002000000000);
        endcase
      end
      8'h57: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(69'h118001000000005000);
          default:
            ctrl = ctrl_word_t'(69'h118001400000005000);
        endcase
      end
      8'h58: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h1a0310000000000000);
          default:
            ctrl = ctrl_word_t'(69'h1a0314002000000000);
        endcase
      end
      8'h59: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h1a0210000000000000);
          default:
            ctrl = ctrl_word_t'(69'h1a0214002000000000);
        endcase
      end
      8'h5A: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h1a8310000000000000);
          default:
            ctrl = ctrl_word_t'(69'h1a8314002000000000);
        endcase
      end
      8'h5B: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h1a8210000000000000);
          default:
            ctrl = ctrl_word_t'(69'h1a8214002000000000);
        endcase
      end
      8'h5C: begin
        case (w0[7:0])
          8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 8'hC1, 
          8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(69'h190014002000000000);
          8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 8'hC8, 
          8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(69'h102714802000000000);
          8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 8'hC9, 
          8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(69'h190014002000000080);
          8'h01:
            ctrl = ctrl_word_t'(69'h190010000000000000);
          8'h08:
            ctrl = ctrl_word_t'(69'h102710800000000000);
          8'h09:
            ctrl = ctrl_word_t'(69'h190010000000000080);
          default:
            ctrl = ctrl_word_t'(69'h000000000000000000);
        endcase
      end
      8'h5D: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h105f05000000000000);
          default:
            ctrl = ctrl_word_t'(69'h105f05400800000000);
        endcase
      end
      8'h5E: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h120000000000000000);
          default:
            ctrl = ctrl_word_t'(69'h120000000000000100);
        endcase
      end
      8'h5F: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h120000000000000400);
          default:
            ctrl = ctrl_word_t'(69'h120000000000000500);
        endcase
      end
      8'h60: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h105d10000000000000);
          default:
            ctrl = ctrl_word_t'(69'h105d14002000000000);
        endcase
      end
      8'h61: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h105e10000000000000);
          default:
            ctrl = ctrl_word_t'(69'h105e14002000000000);
        endcase
      end
      8'h62: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h1069111c2800000000);
          default:
            ctrl = ctrl_word_t'(69'h1069155c2800000000);
        endcase
      end
      8'h63: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h106a111c2800000000);
          default:
            ctrl = ctrl_word_t'(69'h106a155c2800000000);
        endcase
      end
      8'h64: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h1065111c2800000000);
          default:
            ctrl = ctrl_word_t'(69'h1065155c2800000000);
        endcase
      end
      8'h65: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h1066111c2800000000);
          default:
            ctrl = ctrl_word_t'(69'h1066155c2800000000);
        endcase
      end
      8'h66: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h1061109c2800000000);
          default:
            ctrl = ctrl_word_t'(69'h1061149c2800000000);
        endcase
      end
      8'h67: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h1062109c2800000000);
          default:
            ctrl = ctrl_word_t'(69'h1062149c2800000000);
        endcase
      end
      8'h68: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h102d111e2800000000);
          default:
            ctrl = ctrl_word_t'(69'h102d155e2800000000);
        endcase
      end
      8'h69: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h102e111e2800000000);
          default:
            ctrl = ctrl_word_t'(69'h102e155e2800000000);
        endcase
      end
      8'h6A: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h1031111e2800000000);
          default:
            ctrl = ctrl_word_t'(69'h1031155e2800000000);
        endcase
      end
      8'h6B: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h1032111e2800000000);
          default:
            ctrl = ctrl_word_t'(69'h1032155e2800000000);
        endcase
      end
      8'h6C: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h138110000000000000);
          default:
            ctrl = ctrl_word_t'(69'h138114002000000000);
        endcase
      end
      8'h6D: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h138210000000000000);
          default:
            ctrl = ctrl_word_t'(69'h138214002000000000);
        endcase
      end
      8'h6E: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h105d05000000000000);
          default:
            ctrl = ctrl_word_t'(69'h105d05400800000000);
        endcase
      end
      8'h6F: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h105e05000000000000);
          default:
            ctrl = ctrl_word_t'(69'h105e05400800000000);
        endcase
      end
      8'h70: ctrl = ctrl_word_t'(69'h105d34002000000000);
      8'h71: ctrl = ctrl_word_t'(69'h105e34002000000000);
      8'h72: ctrl = ctrl_word_t'(69'h105d06000800000000);
      8'h73: ctrl = ctrl_word_t'(69'h105e06000800000000);
      8'h74: ctrl = ctrl_word_t'(69'h150034002000000000);
      8'h75: ctrl = ctrl_word_t'(69'h105f34002000000000);
      8'h76: begin
        case (w0[7:0])
          8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 
          8'h0C, 8'h0D, 8'h0E, 8'h0F:
            ctrl = ctrl_word_t'(69'h150010000000000000);
          default:
            ctrl = ctrl_word_t'(69'h150014002000000000);
        endcase
      end
      8'h77: ctrl = ctrl_word_t'(69'h105f06000800000000);
      8'h78: ctrl = ctrl_word_t'(69'h000000000000000000);
      8'h79: ctrl = ctrl_word_t'(69'h1b0090000000000000);
      8'h7A: ctrl = ctrl_word_t'(69'h1b8080000000000000);
      8'h7B: begin
        case (w0[7:0])
          8'h1D, 8'h2D, 8'h3D, 8'h4D, 8'h5D, 8'h6D, 8'h7D, 8'h8D, 8'h9D, 8'hAD, 8'hBD, 8'hCD, 
          8'hDD, 8'hED, 8'hFD:
            ctrl = ctrl_word_t'(69'h19808000000000000c);
          8'h00:
            ctrl = ctrl_word_t'(69'h1c8080000000000000);
          8'h08:
            ctrl = ctrl_word_t'(69'h198080000000000008);
          8'h09:
            ctrl = ctrl_word_t'(69'h198080000000000004);
          8'h0A:
            ctrl = ctrl_word_t'(69'h198080000000000000);
          default:
            ctrl = ctrl_word_t'(69'h000000000000000000);
        endcase
      end
      8'h7C: begin
        case (w0[7:0])
          8'h01, 8'h09, 8'h11, 8'h19, 8'h21, 8'h29, 8'h31, 8'h39, 8'h41, 8'h49, 8'h51, 8'h59, 
          8'h61, 8'h69, 8'h71, 8'h79, 8'h81, 8'h89, 8'h91, 8'h99, 8'hA1, 8'hA9, 8'hB1, 8'hB9, 
          8'hC1, 8'hC9, 8'hD1, 8'hD9, 8'hE1, 8'hE9, 8'hF1, 8'hF9:
            ctrl = ctrl_word_t'(69'h108080000110000000);
          8'h02, 8'h0A, 8'h12, 8'h1A, 8'h22, 8'h2A, 8'h32, 8'h3A, 8'h42, 8'h4A, 8'h52, 8'h5A, 
          8'h62, 8'h6A, 8'h72, 8'h7A, 8'h82, 8'h8A, 8'h92, 8'h9A, 8'hA2, 8'hAA, 8'hB2, 8'hBA, 
          8'hC2, 8'hCA, 8'hD2, 8'hDA, 8'hE2, 8'hEA, 8'hF2, 8'hFA:
            ctrl = ctrl_word_t'(69'h108080000108000000);
          8'h03, 8'h0B, 8'h13, 8'h1B, 8'h23, 8'h2B, 8'h33, 8'h3B, 8'h43, 8'h4B, 8'h53, 8'h5B, 
          8'h63, 8'h6B, 8'h73, 8'h7B, 8'h83, 8'h8B, 8'h93, 8'h9B, 8'hA3, 8'hAB, 8'hB3, 8'hBB, 
          8'hC3, 8'hCB, 8'hD3, 8'hDB, 8'hE3, 8'hEB, 8'hF3, 8'hFB:
            ctrl = ctrl_word_t'(69'h108080000100000000);
          8'h04, 8'h0C, 8'h14, 8'h1C, 8'h24, 8'h2C, 8'h34, 8'h3C, 8'h44, 8'h4C, 8'h54, 8'h5C, 
          8'h64, 8'h6C, 8'h74, 8'h7C, 8'h84, 8'h8C, 8'h94, 8'h9C, 8'hA4, 8'hAC, 8'hB4, 8'hBC, 
          8'hC4, 8'hCC, 8'hD4, 8'hDC, 8'hE4, 8'hEC, 8'hF4, 8'hFC:
            ctrl = ctrl_word_t'(69'h108080000018000000);
          8'h05, 8'h0D, 8'h15, 8'h1D, 8'h25, 8'h2D, 8'h35, 8'h3D, 8'h45, 8'h4D, 8'h55, 8'h5D, 
          8'h65, 8'h6D, 8'h75, 8'h7D, 8'h85, 8'h8D, 8'h95, 8'h9D, 8'hA5, 8'hAD, 8'hB5, 8'hBD, 
          8'hC5, 8'hCD, 8'hD5, 8'hDD, 8'hE5, 8'hED, 8'hF5, 8'hFD:
            ctrl = ctrl_word_t'(69'h108080000010000000);
          8'h06, 8'h0E, 8'h16, 8'h1E, 8'h26, 8'h2E, 8'h36, 8'h3E, 8'h46, 8'h4E, 8'h56, 8'h5E, 
          8'h66, 8'h6E, 8'h76, 8'h7E, 8'h86, 8'h8E, 8'h96, 8'h9E, 8'hA6, 8'hAE, 8'hB6, 8'hBE, 
          8'hC6, 8'hCE, 8'hD6, 8'hDE, 8'hE6, 8'hEE, 8'hF6, 8'hFE:
            ctrl = ctrl_word_t'(69'h108080000008000000);
          8'h07, 8'h0F, 8'h17, 8'h1F, 8'h27, 8'h2F, 8'h37, 8'h3F, 8'h47, 8'h4F, 8'h57, 8'h5F, 
          8'h67, 8'h6F, 8'h77, 8'h7F, 8'h87, 8'h8F, 8'h97, 8'h9F, 8'hA7, 8'hAF, 8'hB7, 8'hBF, 
          8'hC7, 8'hCF, 8'hD7, 8'hDF, 8'hE7, 8'hEF, 8'hF7, 8'hFF:
            ctrl = ctrl_word_t'(69'h108080000000000000);
          default:
            ctrl = ctrl_word_t'(69'h108080000118000000);
        endcase
      end
      8'h7D: ctrl = ctrl_word_t'(69'h160080000000000000);
      8'h7E: ctrl = ctrl_word_t'(69'h000000000000000000);
      8'h7F: ctrl = ctrl_word_t'(69'h1c0000000000000000);
      8'h80: ctrl = ctrl_word_t'(69'h100104002000000000);
      8'h81: ctrl = ctrl_word_t'(69'h100204002000000000);
      8'h82: ctrl = ctrl_word_t'(69'h100904002000000000);
      8'h83: ctrl = ctrl_word_t'(69'h100a04002000000000);
      8'h84: ctrl = ctrl_word_t'(69'h101504002000000000);
      8'h85: ctrl = ctrl_word_t'(69'h101604002000000000);
      8'h86: ctrl = ctrl_word_t'(69'h101104002000000000);
      8'h87: ctrl = ctrl_word_t'(69'h101204002000000000);
      8'h88: ctrl = ctrl_word_t'(69'h101904002000000000);
      8'h89: ctrl = ctrl_word_t'(69'h101a04002000000000);
      8'h8A: ctrl = ctrl_word_t'(69'h102904402000000000);
      8'h8B: ctrl = ctrl_word_t'(69'h102a04402000000000);
      8'h8C: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(69'h101d00008800000000);
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(69'h108000000400000000);
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(69'h102100008800000000);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(69'h102500408800000000);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(69'h106d00008800000000);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(69'h105d24000800000000);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(69'h108000000300000000);
          default:
            ctrl = ctrl_word_t'(69'h000000000000000000);
        endcase
      end
      8'h8D: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(69'h101e00008800000000);
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(69'h102200008800000000);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(69'h102600408800000000);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(69'h106e00008800000000);
          8'h07, 8'h17, 8'h27, 8'h37, 8'h47, 8'h57, 8'h67, 8'h77, 8'h87, 8'h97, 8'hA7, 8'hB7, 
          8'hC7, 8'hD7, 8'hE7, 8'hF7:
            ctrl = ctrl_word_t'(69'h105e24400000000000);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(69'h105e24000800000000);
          8'h01:
            ctrl = ctrl_word_t'(69'h108000000000000000);
          8'h03:
            ctrl = ctrl_word_t'(69'h108000000100000000);
          8'h05:
            ctrl = ctrl_word_t'(69'h108000000200000000);
          8'h11:
            ctrl = ctrl_word_t'(69'h108000000000100000);
          8'h13:
            ctrl = ctrl_word_t'(69'h108000000100100000);
          8'h15:
            ctrl = ctrl_word_t'(69'h108000000200100000);
          8'h21:
            ctrl = ctrl_word_t'(69'h108000000000200000);
          8'h23:
            ctrl = ctrl_word_t'(69'h108000000100200000);
          8'h25:
            ctrl = ctrl_word_t'(69'h108000000200200000);
          8'h31:
            ctrl = ctrl_word_t'(69'h108000000000300000);
          8'h33:
            ctrl = ctrl_word_t'(69'h108000000100300000);
          8'h35:
            ctrl = ctrl_word_t'(69'h108000000200300000);
          8'h41:
            ctrl = ctrl_word_t'(69'h108000000000400000);
          8'h43:
            ctrl = ctrl_word_t'(69'h108000000100400000);
          8'h45:
            ctrl = ctrl_word_t'(69'h108000000200400000);
          8'h51:
            ctrl = ctrl_word_t'(69'h108000000000500000);
          8'h53:
            ctrl = ctrl_word_t'(69'h108000000100500000);
          8'h55:
            ctrl = ctrl_word_t'(69'h108000000200500000);
          8'h61:
            ctrl = ctrl_word_t'(69'h108000000000600000);
          8'h63:
            ctrl = ctrl_word_t'(69'h108000000100600000);
          8'h65:
            ctrl = ctrl_word_t'(69'h108000000200600000);
          8'h71:
            ctrl = ctrl_word_t'(69'h108000000000700000);
          8'h73:
            ctrl = ctrl_word_t'(69'h108000000100700000);
          8'h75:
            ctrl = ctrl_word_t'(69'h108000000200700000);
          8'h81:
            ctrl = ctrl_word_t'(69'h108000000000800000);
          8'h83:
            ctrl = ctrl_word_t'(69'h108000000100800000);
          8'h85:
            ctrl = ctrl_word_t'(69'h108000000200800000);
          8'h91:
            ctrl = ctrl_word_t'(69'h108000000000900000);
          8'h93:
            ctrl = ctrl_word_t'(69'h108000000100900000);
          8'h95:
            ctrl = ctrl_word_t'(69'h108000000200900000);
          8'hA1:
            ctrl = ctrl_word_t'(69'h108000000000a00000);
          8'hA3:
            ctrl = ctrl_word_t'(69'h108000000100a00000);
          8'hA5:
            ctrl = ctrl_word_t'(69'h108000000200a00000);
          8'hB1:
            ctrl = ctrl_word_t'(69'h108000000000b00000);
          8'hB3:
            ctrl = ctrl_word_t'(69'h108000000100b00000);
          8'hB5:
            ctrl = ctrl_word_t'(69'h108000000200b00000);
          8'hC1:
            ctrl = ctrl_word_t'(69'h108000000000c00000);
          8'hC3:
            ctrl = ctrl_word_t'(69'h108000000100c00000);
          8'hC5:
            ctrl = ctrl_word_t'(69'h108000000200c00000);
          8'hD1:
            ctrl = ctrl_word_t'(69'h108000000000d00000);
          8'hD3:
            ctrl = ctrl_word_t'(69'h108000000100d00000);
          8'hD5:
            ctrl = ctrl_word_t'(69'h108000000200d00000);
          8'hE1:
            ctrl = ctrl_word_t'(69'h108000000000e00000);
          8'hE3:
            ctrl = ctrl_word_t'(69'h108000000100e00000);
          8'hE5:
            ctrl = ctrl_word_t'(69'h108000000200e00000);
          8'hF1:
            ctrl = ctrl_word_t'(69'h108000000000f00000);
          8'hF3:
            ctrl = ctrl_word_t'(69'h108000000100f00000);
          8'hF5:
            ctrl = ctrl_word_t'(69'h108000000200f00000);
          default:
            ctrl = ctrl_word_t'(69'h000000000000000000);
        endcase
      end
      8'h8E: ctrl = ctrl_word_t'(69'h1d8000000000000003);
      8'h8F: ctrl = ctrl_word_t'(69'h1d8000000000000002);
      8'h90: ctrl = ctrl_word_t'(69'h102b04402000000000);
      8'h91: ctrl = ctrl_word_t'(69'h118000000000002000);
      8'h92: ctrl = ctrl_word_t'(69'h100b04002000000000);
      8'h93: ctrl = ctrl_word_t'(69'h118000000000000000);
      8'h94: ctrl = ctrl_word_t'(69'h105f04002000000000);
      8'h95: ctrl = ctrl_word_t'(69'h118000000000003000);
      8'h96: ctrl = ctrl_word_t'(69'h100304002000000000);
      8'h97: ctrl = ctrl_word_t'(69'h118000000000001000);
      8'h98: ctrl = ctrl_word_t'(69'h1a0304002000000000);
      8'h99: ctrl = ctrl_word_t'(69'h1a0204002000000000);
      8'h9A: ctrl = ctrl_word_t'(69'h1a8304002000000000);
      8'h9B: ctrl = ctrl_word_t'(69'h1a8204002000000000);
      8'h9C: begin
        case (w0[7:0])
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(69'h102700408000000000);
          default:
            ctrl = ctrl_word_t'(69'h000000000000000000);
        endcase
      end
      8'h9D: ctrl = ctrl_word_t'(69'h000000000000000000);
      8'h9E: ctrl = ctrl_word_t'(69'h120000000000000900);
      8'h9F: ctrl = ctrl_word_t'(69'h000000000000000000);
      8'hA0: ctrl = ctrl_word_t'(69'h105d04002000000000);
      8'hA1: ctrl = ctrl_word_t'(69'h105e04002000000000);
      8'hA2: ctrl = ctrl_word_t'(69'h106938008800000000);
      8'hA3: ctrl = ctrl_word_t'(69'h106a38008800000000);
      8'hA4: ctrl = ctrl_word_t'(69'h106538008800000000);
      8'hA5: ctrl = ctrl_word_t'(69'h106638008800000000);
      8'hA6: ctrl = ctrl_word_t'(69'h106138408800000000);
      8'hA7: ctrl = ctrl_word_t'(69'h106238408800000000);
      8'hA8: ctrl = ctrl_word_t'(69'h102d3c008800000000);
      8'hA9: ctrl = ctrl_word_t'(69'h102e3c008800000000);
      8'hAA: ctrl = ctrl_word_t'(69'h10313c008800000000);
      8'hAB: ctrl = ctrl_word_t'(69'h10323c008800000000);
      8'hAC: ctrl = ctrl_word_t'(69'h138100000000000000);
      8'hAD: ctrl = ctrl_word_t'(69'h138200000000000000);
      8'hAE: ctrl = ctrl_word_t'(69'h128100000000000000);
      8'hAF: ctrl = ctrl_word_t'(69'h128200000000000000);
      8'hB0: ctrl = ctrl_word_t'(69'h130000000000000000);
      8'hB1: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(69'h110100000000000000);
          8'h07, 8'h17, 8'h27, 8'h37, 8'h47, 8'h57, 8'h67, 8'h77, 8'h87, 8'h97, 8'hA7, 8'hB7, 
          8'hC7, 8'hD7, 8'hE7, 8'hF7:
            ctrl = ctrl_word_t'(69'h110300000000000000);
          8'h0A, 8'h1A, 8'h2A, 8'h3A, 8'h4A, 8'h5A, 8'h6A, 8'h7A, 8'h8A, 8'h9A, 8'hAA, 8'hBA, 
          8'hCA, 8'hDA, 8'hEA, 8'hFA:
            ctrl = ctrl_word_t'(69'h110200000000000000);
          default:
            ctrl = ctrl_word_t'(69'h000000000000000000);
        endcase
      end
      8'hB2: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(69'h104518008800000000);
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(69'h16bd00040000000000);
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(69'h10451c008800000000);
          8'h03, 8'h13, 8'h23, 8'h33, 8'h43, 8'h53, 8'h63, 8'h73, 8'h83, 8'h93, 8'hA3, 8'hB3, 
          8'hC3, 8'hD3, 8'hE3, 8'hF3:
            ctrl = ctrl_word_t'(69'h16bd00020000000000);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(69'h104918008800000000);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(69'h10491c008800000000);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(69'h104d18008800000000);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(69'h16b500040000000000);
          8'h0A, 8'h1A, 8'h2A, 8'h3A, 8'h4A, 8'h5A, 8'h6A, 8'h7A, 8'h8A, 8'h9A, 8'hAA, 8'hBA, 
          8'hCA, 8'hDA, 8'hEA, 8'hFA:
            ctrl = ctrl_word_t'(69'h104d1c008800000000);
          8'h0B, 8'h1B, 8'h2B, 8'h3B, 8'h4B, 8'h5B, 8'h6B, 8'h7B, 8'h8B, 8'h9B, 8'hAB, 8'hBB, 
          8'hCB, 8'hDB, 8'hEB, 8'hFB:
            ctrl = ctrl_word_t'(69'h16b500020000000000);
          8'h0C, 8'h1C, 8'h2C, 8'h3C, 8'h4C, 8'h5C, 8'h6C, 8'h7C, 8'h8C, 8'h9C, 8'hAC, 8'hBC, 
          8'hCC, 8'hDC, 8'hEC, 8'hFC:
            ctrl = ctrl_word_t'(69'h105118008800000000);
          8'h0E, 8'h1E, 8'h2E, 8'h3E, 8'h4E, 8'h5E, 8'h6E, 8'h7E, 8'h8E, 8'h9E, 8'hAE, 8'hBE, 
          8'hCE, 8'hDE, 8'hEE, 8'hFE:
            ctrl = ctrl_word_t'(69'h10511c008800000000);
          default:
            ctrl = ctrl_word_t'(69'h000000000000000000);
        endcase
      end
      8'hB3: begin
        case (w0[7:0])
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            ctrl = ctrl_word_t'(69'h16be00040000000000);
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(69'h10461c008800000000);
          8'h03, 8'h13, 8'h23, 8'h33, 8'h43, 8'h53, 8'h63, 8'h73, 8'h83, 8'h93, 8'hA3, 8'hB3, 
          8'hC3, 8'hD3, 8'hE3, 8'hF3:
            ctrl = ctrl_word_t'(69'h16be00020000000000);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(69'h104a18008800000000);
          8'h05, 8'h15, 8'h25, 8'h35, 8'h45, 8'h55, 8'h65, 8'h75, 8'h85, 8'h95, 8'hA5, 8'hB5, 
          8'hC5, 8'hD5, 8'hE5, 8'hF5:
            ctrl = ctrl_word_t'(69'h16bf00040000000000);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(69'h104a1c008800000000);
          8'h07, 8'h17, 8'h27, 8'h37, 8'h47, 8'h57, 8'h67, 8'h77, 8'h87, 8'h97, 8'hA7, 8'hB7, 
          8'hC7, 8'hD7, 8'hE7, 8'hF7:
            ctrl = ctrl_word_t'(69'h16bf00020000000000);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(69'h104e18008800000000);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            ctrl = ctrl_word_t'(69'h16b600040000000000);
          8'h0A, 8'h1A, 8'h2A, 8'h3A, 8'h4A, 8'h5A, 8'h6A, 8'h7A, 8'h8A, 8'h9A, 8'hAA, 8'hBA, 
          8'hCA, 8'hDA, 8'hEA, 8'hFA:
            ctrl = ctrl_word_t'(69'h104e1c008800000000);
          8'h0B, 8'h1B, 8'h2B, 8'h3B, 8'h4B, 8'h5B, 8'h6B, 8'h7B, 8'h8B, 8'h9B, 8'hAB, 8'hBB, 
          8'hCB, 8'hDB, 8'hEB, 8'hFB:
            ctrl = ctrl_word_t'(69'h16b600020000000000);
          8'h0C, 8'h1C, 8'h2C, 8'h3C, 8'h4C, 8'h5C, 8'h6C, 8'h7C, 8'h8C, 8'h9C, 8'hAC, 8'hBC, 
          8'hCC, 8'hDC, 8'hEC, 8'hFC:
            ctrl = ctrl_word_t'(69'h105218008800000000);
          8'h0D, 8'h1D, 8'h2D, 8'h3D, 8'h4D, 8'h5D, 8'h6D, 8'h7D, 8'h8D, 8'h9D, 8'hAD, 8'hBD, 
          8'hCD, 8'hDD, 8'hED, 8'hFD:
            ctrl = ctrl_word_t'(69'h16b700040000000000);
          8'h0E, 8'h1E, 8'h2E, 8'h3E, 8'h4E, 8'h5E, 8'h6E, 8'h7E, 8'h8E, 8'h9E, 8'hAE, 8'hBE, 
          8'hCE, 8'hDE, 8'hEE, 8'hFE:
            ctrl = ctrl_word_t'(69'h10521c008800000000);
          8'h0F, 8'h1F, 8'h2F, 8'h3F, 8'h4F, 8'h5F, 8'h6F, 8'h7F, 8'h8F, 8'h9F, 8'hAF, 8'hBF, 
          8'hCF, 8'hDF, 8'hEF, 8'hFF:
            ctrl = ctrl_word_t'(69'h16b700020000000000);
          default:
            ctrl = ctrl_word_t'(69'h104618008800000000);
        endcase
      end
      8'hB4: ctrl = ctrl_word_t'(69'h100504002000000000);
      8'hB5: ctrl = ctrl_word_t'(69'h100604002000000000);
      8'hB6: ctrl = ctrl_word_t'(69'h100d04002000000000);
      8'hB7: ctrl = ctrl_word_t'(69'h100e04002000000000);
      8'hB8: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(69'h1d0000000000000080);
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(69'h1d0000000000000000);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(69'h1d0000000000000090);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(69'h1d0000000000000010);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(69'h1d00000000000000a0);
          8'h0A, 8'h1A, 8'h2A, 8'h3A, 8'h4A, 8'h5A, 8'h6A, 8'h7A, 8'h8A, 8'h9A, 8'hAA, 8'hBA, 
          8'hCA, 8'hDA, 8'hEA, 8'hFA:
            ctrl = ctrl_word_t'(69'h1d0000000000000020);
          8'h0C, 8'h1C, 8'h2C, 8'h3C, 8'h4C, 8'h5C, 8'h6C, 8'h7C, 8'h8C, 8'h9C, 8'hAC, 8'hBC, 
          8'hCC, 8'hDC, 8'hEC, 8'hFC:
            ctrl = ctrl_word_t'(69'h1d00000000000000b0);
          8'h0E, 8'h1E, 8'h2E, 8'h3E, 8'h4E, 8'h5E, 8'h6E, 8'h7E, 8'h8E, 8'h9E, 8'hAE, 8'hBE, 
          8'hCE, 8'hDE, 8'hEE, 8'hFE:
            ctrl = ctrl_word_t'(69'h1d0000000000000030);
          default:
            ctrl = ctrl_word_t'(69'h000000000000000000);
        endcase
      end
      8'hB9: ctrl = ctrl_word_t'(69'h000000000000000000);
      8'hBA: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(69'h178100000000000000);
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            case (w1_lo)
            4'h8, 4'h9, 4'hA, 4'hB, 4'hC, 4'hD, 4'hE, 4'hF: ctrl = ctrl_word_t'(69'h170100000000000000);
            default: ctrl = ctrl_word_t'(69'h170100000000000010);
          endcase
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(69'h180100000000000000);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(69'h178100000000000010);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(69'h180100000000000010);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(69'h178100000000000020);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            case (w1_lo)
            4'h8, 4'h9, 4'hA, 4'hB, 4'hC, 4'hD, 4'hE, 4'hF: ctrl = ctrl_word_t'(69'h170100000000000020);
            default: ctrl = ctrl_word_t'(69'h170100000000000030);
          endcase
          8'h0A, 8'h1A, 8'h2A, 8'h3A, 8'h4A, 8'h5A, 8'h6A, 8'h7A, 8'h8A, 8'h9A, 8'hAA, 8'hBA, 
          8'hCA, 8'hDA, 8'hEA, 8'hFA:
            ctrl = ctrl_word_t'(69'h180100000000000020);
          8'h0C, 8'h1C, 8'h2C, 8'h3C, 8'h4C, 8'h5C, 8'h6C, 8'h7C, 8'h8C, 8'h9C, 8'hAC, 8'hBC, 
          8'hCC, 8'hDC, 8'hEC, 8'hFC:
            ctrl = ctrl_word_t'(69'h178100000000000030);
          8'h0E, 8'h1E, 8'h2E, 8'h3E, 8'h4E, 8'h5E, 8'h6E, 8'h7E, 8'h8E, 8'h9E, 8'hAE, 8'hBE, 
          8'hCE, 8'hDE, 8'hEE, 8'hFE:
            ctrl = ctrl_word_t'(69'h180100000000000030);
          default:
            ctrl = ctrl_word_t'(69'h000000000000000000);
        endcase
      end
      8'hBB: begin
        case (w0[7:0])
          8'h00, 8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 
          8'hC0, 8'hD0, 8'hE0, 8'hF0:
            ctrl = ctrl_word_t'(69'h178200000000000000);
          8'h01, 8'h11, 8'h21, 8'h31, 8'h41, 8'h51, 8'h61, 8'h71, 8'h81, 8'h91, 8'hA1, 8'hB1, 
          8'hC1, 8'hD1, 8'hE1, 8'hF1:
            case (w1_lo)
            4'h8, 4'h9, 4'hA, 4'hB, 4'hC, 4'hD, 4'hE, 4'hF: ctrl = ctrl_word_t'(69'h170200000000000000);
            default: ctrl = ctrl_word_t'(69'h170200000000000010);
          endcase
          8'h02, 8'h12, 8'h22, 8'h32, 8'h42, 8'h52, 8'h62, 8'h72, 8'h82, 8'h92, 8'hA2, 8'hB2, 
          8'hC2, 8'hD2, 8'hE2, 8'hF2:
            ctrl = ctrl_word_t'(69'h180200000000000000);
          8'h04, 8'h14, 8'h24, 8'h34, 8'h44, 8'h54, 8'h64, 8'h74, 8'h84, 8'h94, 8'hA4, 8'hB4, 
          8'hC4, 8'hD4, 8'hE4, 8'hF4:
            ctrl = ctrl_word_t'(69'h178200000000000010);
          8'h06, 8'h16, 8'h26, 8'h36, 8'h46, 8'h56, 8'h66, 8'h76, 8'h86, 8'h96, 8'hA6, 8'hB6, 
          8'hC6, 8'hD6, 8'hE6, 8'hF6:
            ctrl = ctrl_word_t'(69'h180200000000000010);
          8'h08, 8'h18, 8'h28, 8'h38, 8'h48, 8'h58, 8'h68, 8'h78, 8'h88, 8'h98, 8'hA8, 8'hB8, 
          8'hC8, 8'hD8, 8'hE8, 8'hF8:
            ctrl = ctrl_word_t'(69'h178200000000000020);
          8'h09, 8'h19, 8'h29, 8'h39, 8'h49, 8'h59, 8'h69, 8'h79, 8'h89, 8'h99, 8'hA9, 8'hB9, 
          8'hC9, 8'hD9, 8'hE9, 8'hF9:
            case (w1_lo)
            4'h8, 4'h9, 4'hA, 4'hB, 4'hC, 4'hD, 4'hE, 4'hF: ctrl = ctrl_word_t'(69'h170200000000000020);
            default: ctrl = ctrl_word_t'(69'h170200000000000030);
          endcase
          8'h0A, 8'h1A, 8'h2A, 8'h3A, 8'h4A, 8'h5A, 8'h6A, 8'h7A, 8'h8A, 8'h9A, 8'hAA, 8'hBA, 
          8'hCA, 8'hDA, 8'hEA, 8'hFA:
            ctrl = ctrl_word_t'(69'h180200000000000020);
          8'h0C, 8'h1C, 8'h2C, 8'h3C, 8'h4C, 8'h5C, 8'h6C, 8'h7C, 8'h8C, 8'h9C, 8'hAC, 8'hBC, 
          8'hCC, 8'hDC, 8'hEC, 8'hFC:
            ctrl = ctrl_word_t'(69'h178200000000000030);
          8'h0E, 8'h1E, 8'h2E, 8'h3E, 8'h4E, 8'h5E, 8'h6E, 8'h7E, 8'h8E, 8'h9E, 8'hAE, 8'hBE, 
          8'hCE, 8'hDE, 8'hEE, 8'hFE:
            ctrl = ctrl_word_t'(69'h180200000000000030);
          default:
            ctrl = ctrl_word_t'(69'h000000000000000000);
        endcase
      end
      8'hBC: ctrl = ctrl_word_t'(69'h144800000000000000);
      8'hBD: ctrl = ctrl_word_t'(69'h105e38000800000000);
      8'hBE: ctrl = ctrl_word_t'(69'h144400000000000000);
      8'hBF: ctrl = ctrl_word_t'(69'h000000000000000000);
      8'hC0: ctrl = ctrl_word_t'(69'h105d40001000000000);
      8'hC1: ctrl = ctrl_word_t'(69'h105d40001000000000);
      8'hC2: ctrl = ctrl_word_t'(69'h105d40001000000000);
      8'hC3: ctrl = ctrl_word_t'(69'h105d40001000000000);
      8'hC4: ctrl = ctrl_word_t'(69'h105d40001000000000);
      8'hC5: ctrl = ctrl_word_t'(69'h105d40001000000000);
      8'hC6: ctrl = ctrl_word_t'(69'h105d40001000000000);
      8'hC7: ctrl = ctrl_word_t'(69'h105d40001000000000);
      8'hC8: ctrl = ctrl_word_t'(69'h105d40001000000000);
      8'hC9: ctrl = ctrl_word_t'(69'h105d40001000000000);
      8'hCA: ctrl = ctrl_word_t'(69'h105d40001000000000);
      8'hCB: ctrl = ctrl_word_t'(69'h105d40001000000000);
      8'hCC: ctrl = ctrl_word_t'(69'h105d40001000000000);
      8'hCD: ctrl = ctrl_word_t'(69'h105d40001000000000);
      8'hCE: ctrl = ctrl_word_t'(69'h105d40001000000000);
      8'hCF: ctrl = ctrl_word_t'(69'h105d40001000000000);
      8'hD0: ctrl = ctrl_word_t'(69'h120000000000000800);
      8'hD1: ctrl = ctrl_word_t'(69'h120000000000000800);
      8'hD2: ctrl = ctrl_word_t'(69'h120000000000000800);
      8'hD3: ctrl = ctrl_word_t'(69'h120000000000000800);
      8'hD4: ctrl = ctrl_word_t'(69'h120000000000000800);
      8'hD5: ctrl = ctrl_word_t'(69'h120000000000000800);
      8'hD6: ctrl = ctrl_word_t'(69'h120000000000000800);
      8'hD7: ctrl = ctrl_word_t'(69'h120000000000000800);
      8'hD8: ctrl = ctrl_word_t'(69'h120000000000000800);
      8'hD9: ctrl = ctrl_word_t'(69'h120000000000000800);
      8'hDA: ctrl = ctrl_word_t'(69'h120000000000000800);
      8'hDB: ctrl = ctrl_word_t'(69'h120000000000000800);
      8'hDC: ctrl = ctrl_word_t'(69'h120000000000000800);
      8'hDD: ctrl = ctrl_word_t'(69'h120000000000000800);
      8'hDE: ctrl = ctrl_word_t'(69'h120000000000000800);
      8'hDF: ctrl = ctrl_word_t'(69'h120000000000000800);
      8'hE0: ctrl = ctrl_word_t'(69'h120000000000000300);
      8'hE1: ctrl = ctrl_word_t'(69'h120000000000000300);
      8'hE2: ctrl = ctrl_word_t'(69'h120000000000000300);
      8'hE3: ctrl = ctrl_word_t'(69'h120000000000000300);
      8'hE4: ctrl = ctrl_word_t'(69'h120000000000000300);
      8'hE5: ctrl = ctrl_word_t'(69'h120000000000000300);
      8'hE6: ctrl = ctrl_word_t'(69'h120000000000000300);
      8'hE7: ctrl = ctrl_word_t'(69'h120000000000000300);
      8'hE8: ctrl = ctrl_word_t'(69'h120000000000000300);
      8'hE9: ctrl = ctrl_word_t'(69'h120000000000000300);
      8'hEA: ctrl = ctrl_word_t'(69'h120000000000000300);
      8'hEB: ctrl = ctrl_word_t'(69'h120000000000000300);
      8'hEC: ctrl = ctrl_word_t'(69'h120000000000000300);
      8'hED: ctrl = ctrl_word_t'(69'h120000000000000300);
      8'hEE: ctrl = ctrl_word_t'(69'h120000000000000300);
      8'hEF: ctrl = ctrl_word_t'(69'h120000000000000300);
      8'hF0: ctrl = ctrl_word_t'(69'h120000000000000a00);
      8'hF1: ctrl = ctrl_word_t'(69'h120000000000000a00);
      8'hF2: ctrl = ctrl_word_t'(69'h120000000000000a00);
      8'hF3: ctrl = ctrl_word_t'(69'h120000000000000a00);
      8'hF4: ctrl = ctrl_word_t'(69'h120000000000000a00);
      8'hF5: ctrl = ctrl_word_t'(69'h120000000000000a00);
      8'hF6: ctrl = ctrl_word_t'(69'h120000000000000a00);
      8'hF7: ctrl = ctrl_word_t'(69'h120000000000000a00);
      8'hF8: ctrl = ctrl_word_t'(69'h120000000000000a00);
      8'hF9: ctrl = ctrl_word_t'(69'h120000000000000a00);
      8'hFA: ctrl = ctrl_word_t'(69'h120000000000000a00);
      8'hFB: ctrl = ctrl_word_t'(69'h120000000000000a00);
      8'hFC: ctrl = ctrl_word_t'(69'h120000000000000a00);
      8'hFD: ctrl = ctrl_word_t'(69'h120000000000000a00);
      8'hFE: ctrl = ctrl_word_t'(69'h120000000000000a00);
      8'hFF: ctrl = ctrl_word_t'(69'h120000000000000a00);
      default: ctrl = ctrl_word_t'(W'(0));
    endcase
  end

endmodule
