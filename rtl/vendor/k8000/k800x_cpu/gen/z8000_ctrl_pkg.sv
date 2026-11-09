// DERIVED FILE, but a COMMITTED SOURCE of k8000: check it in, review its
// diffs, and build from it. Nothing in k8000's lint/build/test reads any
// other repo.
//
// Do not hand-edit: it is emitted by cmd/decoderom from the Z8000 Go golden
// model, and 'make refresh-rtl' (maintainers only, needs that model) will
// overwrite it. What proves it correct HERE is tb_decode replaying the
// committed vectors/k800x_cpu/decode/decode.vec -- no external repo needed.
//
// z8000_ctrl_pkg: the decode-ROM control word (Go CtrlWord, sim/cpu/decode.go)
// as a packed struct, plus every enum it references. Field order below is
// MSB first; CTRL_W = 69 bits. The .vec files and the generated decoder
// use exactly this packing.

// A constants package is a library: most members are unused by any one
// consumer, so UNUSEDPARAM is waived for this file only.
/* verilator lint_off UNUSEDPARAM */
package z8000_ctrl_pkg;

  localparam int CTRL_W = 69;

  // ---- InstrClass (28 values, 5 bits) ----
  localparam int CLS_W = 5;
  localparam logic [4:0] CLS_UNIFIED = 5'd0;
  localparam logic [4:0] CLS_FCW_OP = 5'd1;
  localparam logic [4:0] CLS_EXTS = 5'd2;
  localparam logic [4:0] CLS_STACK = 5'd3;
  localparam logic [4:0] CLS_BRANCH = 5'd4;
  localparam logic [4:0] CLS_TCC = 5'd5;
  localparam logic [4:0] CLS_DAB = 5'd6;
  localparam logic [4:0] CLS_EXCHANGE = 5'd7;
  localparam logic [4:0] CLS_BCDROTATE = 5'd8;
  localparam logic [4:0] CLS_BIT_DYNAMIC = 5'd9;
  localparam logic [4:0] CLS_LEA = 5'd10;
  localparam logic [4:0] CLS_IO = 5'd11;
  localparam logic [4:0] CLS_LDCTL = 5'd12;
  localparam logic [4:0] CLS_SHIFT = 5'd13;
  localparam logic [4:0] CLS_BLOCK_TRANSFER = 5'd14;
  localparam logic [4:0] CLS_BLOCK_COMPARE = 5'd15;
  localparam logic [4:0] CLS_BLOCK_STRING = 5'd16;
  localparam logic [4:0] CLS_BLOCK_IO = 5'd17;
  localparam logic [4:0] CLS_LDM = 5'd18;
  localparam logic [4:0] CLS_MULTI_PROC = 5'd19;
  localparam logic [4:0] CLS_MUL = 5'd20;
  localparam logic [4:0] CLS_DIV = 5'd21;
  localparam logic [4:0] CLS_LDPS = 5'd22;
  localparam logic [4:0] CLS_HALT = 5'd23;
  localparam logic [4:0] CLS_SYS_CALL = 5'd24;
  localparam logic [4:0] CLS_IRET = 5'd25;
  localparam logic [4:0] CLS_TRANSLATE = 5'd26;
  localparam logic [4:0] CLS_EPU = 5'd27;

  // ---- Op (28 values, 5 bits) ----
  localparam int ALUOP_W = 5;
  localparam logic [4:0] OP_ADD = 5'd0;
  localparam logic [4:0] OP_ADC = 5'd1;
  localparam logic [4:0] OP_SUB = 5'd2;
  localparam logic [4:0] OP_SBC = 5'd3;
  localparam logic [4:0] OP_AND = 5'd4;
  localparam logic [4:0] OP_OR = 5'd5;
  localparam logic [4:0] OP_XOR = 5'd6;
  localparam logic [4:0] OP_COM = 5'd7;
  localparam logic [4:0] OP_NEG = 5'd8;
  localparam logic [4:0] OP_TEST = 5'd9;
  localparam logic [4:0] OP_CP = 5'd10;
  localparam logic [4:0] OP_INC = 5'd11;
  localparam logic [4:0] OP_DEC = 5'd12;
  localparam logic [4:0] OP_SLA = 5'd13;
  localparam logic [4:0] OP_SRA = 5'd14;
  localparam logic [4:0] OP_SLL = 5'd15;
  localparam logic [4:0] OP_SRL = 5'd16;
  localparam logic [4:0] OP_RL = 5'd17;
  localparam logic [4:0] OP_RR = 5'd18;
  localparam logic [4:0] OP_RLC = 5'd19;
  localparam logic [4:0] OP_RRC = 5'd20;
  localparam logic [4:0] OP_DAB = 5'd21;
  localparam logic [4:0] OP_EXTS = 5'd22;
  localparam logic [4:0] OP_LD = 5'd23;
  localparam logic [4:0] OP_BIT = 5'd24;
  localparam logic [4:0] OP_SET = 5'd25;
  localparam logic [4:0] OP_RES = 5'd26;
  localparam logic [4:0] OP_TSET = 5'd27;

  // ---- SrcSel (17 values, 5 bits) ----
  localparam int SRC_W = 5;
  localparam logic [4:0] SRC_NONE = 5'd0;
  localparam logic [4:0] SRC_REG = 5'd1;
  localparam logic [4:0] SRC_IMM = 5'd2;
  localparam logic [4:0] SRC_IR = 5'd3;
  localparam logic [4:0] SRC_DA = 5'd4;
  localparam logic [4:0] SRC_X = 5'd5;
  localparam logic [4:0] SRC_ONE = 5'd6;
  localparam logic [4:0] SRC_TWO = 5'd7;
  localparam logic [4:0] SRC_NIB3_CNT = 5'd8;
  localparam logic [4:0] SRC_ZERO = 5'd9;
  localparam logic [4:0] SRC_IMM2 = 5'd10;
  localparam logic [4:0] SRC_PCREL = 5'd11;
  localparam logic [4:0] SRC_BASED = 5'd12;
  localparam logic [4:0] SRC_BX = 5'd13;
  localparam logic [4:0] SRC_NIB3_BIT = 5'd14;
  localparam logic [4:0] SRC_NIB3_CNT_PLUS1 = 5'd15;
  localparam logic [4:0] SRC_OP_LO_BYTE = 5'd16;

  // ---- DstSel (9 values, 4 bits) ----
  localparam int DST_W = 4;
  localparam logic [3:0] DST_REG = 4'd0;
  localparam logic [3:0] DST_NONE = 4'd1;
  localparam logic [3:0] DST_FLAGS_ONLY = 4'd2;
  localparam logic [3:0] DST_IR = 4'd3;
  localparam logic [3:0] DST_DA = 4'd4;
  localparam logic [3:0] DST_X = 4'd5;
  localparam logic [3:0] DST_PCREL = 4'd6;
  localparam logic [3:0] DST_BASED = 4'd7;
  localparam logic [3:0] DST_BX = 4'd8;

  // ---- RegSel (3 values, 2 bits) ----
  localparam int REGSEL_W = 2;
  localparam logic [1:0] REG_NIB3 = 2'd0;
  localparam logic [1:0] REG_NIB2 = 2'd1;
  localparam logic [1:0] REG_NIB1 = 2'd2;

  // ---- FcwOpKind (5 values, 3 bits) ----
  localparam int FCWOP_W = 3;
  localparam logic [2:0] FCW_SET = 3'd0;
  localparam logic [2:0] FCW_CLEAR = 3'd1;
  localparam logic [2:0] FCW_TOGGLE = 3'd2;
  localparam logic [2:0] FCW_LOAD_LO = 3'd3;
  localparam logic [2:0] FCW_STORE_LO = 3'd4;

  // ---- StackMode (9 values, 4 bits) ----
  localparam int STK_W = 4;
  localparam logic [3:0] STACK_PUSH = 4'd0;
  localparam logic [3:0] STACK_POP = 4'd1;
  localparam logic [3:0] STACK_PUSH_L = 4'd2;
  localparam logic [3:0] STACK_POP_L = 4'd3;
  localparam logic [3:0] STACK_PUSH_SRC = 4'd4;
  localparam logic [3:0] STACK_POP_DST = 4'd5;
  localparam logic [3:0] STACK_PUSH_LSRC = 4'd6;
  localparam logic [3:0] STACK_POP_LDST = 4'd7;
  localparam logic [3:0] STACK_PUSH_IMM = 4'd8;

  // ---- BranchMode (11 values, 4 bits) ----
  localparam int BR_W = 4;
  localparam logic [3:0] BRANCH_JP__DA = 4'd0;
  localparam logic [3:0] BRANCH_JP__X = 4'd1;
  localparam logic [3:0] BRANCH_JP__IR = 4'd2;
  localparam logic [3:0] BRANCH_JR = 4'd3;
  localparam logic [3:0] BRANCH_CALL__DA = 4'd4;
  localparam logic [3:0] BRANCH_CALL__X = 4'd5;
  localparam logic [3:0] BRANCH_CALL__IR = 4'd6;
  localparam logic [3:0] BRANCH_CALR = 4'd7;
  localparam logic [3:0] BRANCH_CALR12 = 4'd8;
  localparam logic [3:0] BRANCH_RET = 4'd9;
  localparam logic [3:0] BRANCH_DJNZ = 4'd10;

  // ---- MPOpKind (4 values, 2 bits) ----
  localparam int MP_W = 2;
  localparam logic [1:0] MPBIT = 2'd0;
  localparam logic [1:0] MPRES = 2'd1;
  localparam logic [1:0] MPSET = 2'd2;
  localparam logic [1:0] MPREQ = 2'd3;

  // ---- EPUKindSel (4 values, 2 bits) ----
  localparam int EPU_W = 2;
  localparam logic [1:0] EPU_NONE = 2'd0;
  localparam logic [1:0] EPU_MEM = 2'd1;
  localparam logic [1:0] EPU_CPU = 2'd2;
  localparam logic [1:0] EPU_FLAGS = 2'd3;

  // ---- operand width code ----
  localparam logic [1:0] WIDTH_NONE = 2'd0;
  localparam logic [1:0] WIDTH_BYTE = 2'd1;
  localparam logic [1:0] WIDTH_WORD = 2'd2;
  localparam logic [1:0] WIDTH_LONG = 2'd3;

  // ---- the control word ----
  typedef struct packed {
    logic        valid;        // 1 = defined opcode (ROM hit); 0 = undefined -> privileged-instruction trap
    logic [4:0]  exec;         // InstrClass: execute-phase FSM variant
    logic [4:0]  alu_op;       // alu.Op
    logic [1:0]  width;        // operand width: 0=none 1=byte 2=word 3=long
    logic        priv;         // privileged instruction
    logic [4:0]  src2;         // SrcSel: second source operand select
    logic [3:0]  dst;          // DstSel: result destination select
    logic [4:0]  count;        // SrcSel: RMW/shift count operand select
    logic [1:0]  src1_nib;     // RegSel: nibble selecting src1 register
    logic [1:0]  src2_nib;     // RegSel: nibble selecting src2 register
    logic [1:0]  dst_nib;      // RegSel: nibble selecting dst register
    logic [2:0]  fcw_op;       // FcwOpKind (ClsFcwOp)
    logic [15:0] fcw_mask;     // FCW bit mask (ClsFcwOp)
    logic [3:0]  stk_mode;     // StackMode (ClsStack)
    logic [3:0]  br_mode;      // BranchMode (ClsBranch)
    logic        io_write;     // I/O direction / LDM store
    logic        io_spec;      // special I/O (status 0011)
    logic        block_decr;   // block op: decrement pointers
    logic        block_rept;   // block op: repeat
    logic [1:0]  mp_op;        // MPOpKind (ClsMultiProc)
    logic [1:0]  epu_kind;     // EPUKindSel (ClsEPU)
  } ctrl_word_t;

  // LSB position of each field inside the packed word (for tb/tools):
  localparam int CTRL_POS_VALID = 68;
  localparam int CTRL_POS_EXEC = 63;
  localparam int CTRL_POS_ALU_OP = 58;
  localparam int CTRL_POS_WIDTH = 56;
  localparam int CTRL_POS_PRIV = 55;
  localparam int CTRL_POS_SRC2 = 50;
  localparam int CTRL_POS_DST = 46;
  localparam int CTRL_POS_COUNT = 41;
  localparam int CTRL_POS_SRC1_NIB = 39;
  localparam int CTRL_POS_SRC2_NIB = 37;
  localparam int CTRL_POS_DST_NIB = 35;
  localparam int CTRL_POS_FCW_OP = 32;
  localparam int CTRL_POS_FCW_MASK = 16;
  localparam int CTRL_POS_STK_MODE = 12;
  localparam int CTRL_POS_BR_MODE = 8;
  localparam int CTRL_POS_IO_WRITE = 7;
  localparam int CTRL_POS_IO_SPEC = 6;
  localparam int CTRL_POS_BLOCK_DECR = 5;
  localparam int CTRL_POS_BLOCK_REPT = 4;
  localparam int CTRL_POS_MP_OP = 2;
  localparam int CTRL_POS_EPU_KIND = 0;

endpackage
/* verilator lint_on UNUSEDPARAM */
