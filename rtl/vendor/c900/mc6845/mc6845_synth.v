module mc6845
  (input  CLOCK,
   input  CLKEN,
   input  CLKEN_CPU,
   input  nRESET,
   input  ENABLE,
   input  R_nW,
   input  RS,
   input  [7:0] DI,
   input  LPSTB,
   input  VGA,
   output [7:0] DO,
   output DO_VALID,
   output VSYNC,
   output HSYNC,
   output DE,
   output CURSOR,
   output [13:0] MA,
   output [4:0] RA,
   output [3:0] test,
   output [7:0] R1_ACTIVE,
   output H_DISPLAY_O,
   output V_DISPLAY_O);
  wire [4:0] addr_reg;
  wire [7:0] r00_h_total;
  wire [7:0] r01_h_displayed;
  wire [7:0] r02_h_sync_pos;
  wire [3:0] r03_h_sync_width;
  wire [6:0] r04_v_total;
  wire [4:0] r05_v_total_adj;
  wire [6:0] r06_v_displayed;
  wire [6:0] r07_v_sync_pos;
  wire [7:0] r08_interlace;
  wire [4:0] r09_max_scanline_addr;
  wire [1:0] r10_cursor_mode;
  wire [4:0] r10_cursor_start;
  wire [4:0] r11_cursor_end;
  wire [5:0] r12_start_addr_h;
  wire [7:0] r13_start_addr_l;
  wire [5:0] r14_cursor_h;
  wire [7:0] r15_cursor_l;
  wire [5:0] r16_light_pen_h;
  wire [7:0] r17_light_pen_l;
  wire [7:0] h_counter;
  wire [3:0] h_sync_counter;
  wire [6:0] row_counter;
  wire [6:0] row_counter_next;
  wire [4:0] line_counter;
  wire [4:0] line_counter_next;
  wire [3:0] v_sync_counter;
  wire [4:0] field_counter;
  wire h_display;
  wire hs;
  wire hs_started;
  wire v_display;
  wire vs;
  wire vs_hit;
  wire vs_hit_last;
  wire vs_started;
  wire vs_even;
  wire vs_odd;
  wire odd_field;
  wire [13:0] ma_i;
  wire [3:0] lpstb_sync;
  wire de0;
  wire cursor0;
  wire interlaced_video;
  wire [4:0] max_scanline;
  wire [4:0] adj_scanline;
  wire [13:0] ma_row;
  wire in_adj;
  wire adj_in_progress;
  wire [2:0] sol;
  wire eom_latched;
  wire eof_latched;
  wire first_scanline;
  wire extra_scanline;
  wire new_frame;
  wire r00_h_total_hit;
  wire max_scanline_hit;
  wire last_prev_line;
  wire hs_d1;
  wire [4:0] hsync_line_latch;
  wire [6:0] hsync_row_latch;
  wire [4:0] n13_o;
  wire [4:0] n14_o;
  wire [3:0] n15_o;
  wire [4:0] n17_o;
  wire [1:0] n18_o;
  wire n20_o;
  wire [4:0] n21_o;
  wire n23_o;
  wire n24_o;
  wire n25_o;
  wire n26_o;
  wire [4:0] n29_o;
  wire [1:0] n30_o;
  wire n32_o;
  wire n33_o;
  wire [4:0] n34_o;
  wire n36_o;
  wire n37_o;
  wire n40_o;
  wire n41_o;
  wire n42_o;
  wire n43_o;
  wire n44_o;
  wire n45_o;
  wire n46_o;
  wire n47_o;
  wire n48_o;
  wire n49_o;
  wire n53_o;
  wire [7:0] n56_o;
  wire n58_o;
  wire n60_o;
  wire [7:0] n62_o;
  wire n64_o;
  wire n66_o;
  wire [3:0] n67_o;
  reg [7:0] n69_o;
  reg n75_o;
  wire [7:0] n77_o;
  wire n80_o;
  wire n82_o;
  wire [4:0] n83_o;
  wire n85_o;
  wire n87_o;
  wire n89_o;
  wire [3:0] n91_o;
  wire n93_o;
  wire [6:0] n94_o;
  wire n96_o;
  wire [4:0] n97_o;
  wire n99_o;
  wire [6:0] n100_o;
  wire n102_o;
  wire [6:0] n103_o;
  wire n105_o;
  wire n107_o;
  wire [4:0] n108_o;
  wire n110_o;
  wire [1:0] n111_o;
  wire [4:0] n112_o;
  wire n114_o;
  wire [4:0] n115_o;
  wire n117_o;
  wire [5:0] n118_o;
  wire n120_o;
  wire n122_o;
  wire [5:0] n123_o;
  wire n125_o;
  wire n127_o;
  wire [15:0] n128_o;
  reg [7:0] n129_o;
  reg [7:0] n130_o;
  reg [7:0] n131_o;
  reg [3:0] n133_o;
  reg [6:0] n134_o;
  reg [4:0] n135_o;
  reg [6:0] n136_o;
  reg [6:0] n137_o;
  reg [7:0] n138_o;
  reg [4:0] n139_o;
  reg [1:0] n140_o;
  reg [4:0] n141_o;
  reg [4:0] n142_o;
  reg [5:0] n143_o;
  reg [7:0] n144_o;
  reg [5:0] n145_o;
  reg [7:0] n146_o;
  wire [4:0] n147_o;
  wire [7:0] n148_o;
  wire [7:0] n149_o;
  wire [7:0] n150_o;
  wire [3:0] n152_o;
  wire [6:0] n153_o;
  wire [4:0] n154_o;
  wire [6:0] n155_o;
  wire [6:0] n156_o;
  wire [7:0] n157_o;
  wire [4:0] n158_o;
  wire [1:0] n159_o;
  wire [4:0] n160_o;
  wire [4:0] n161_o;
  wire [5:0] n162_o;
  wire [7:0] n163_o;
  wire [5:0] n164_o;
  wire [7:0] n165_o;
  wire n166_o;
  wire [7:0] n167_o;
  wire [7:0] n168_o;
  wire [7:0] n169_o;
  wire [3:0] n171_o;
  wire [6:0] n172_o;
  wire [4:0] n173_o;
  wire [6:0] n174_o;
  wire [6:0] n175_o;
  wire [7:0] n176_o;
  wire [4:0] n177_o;
  wire [1:0] n178_o;
  wire [4:0] n179_o;
  wire [4:0] n180_o;
  wire [5:0] n181_o;
  wire [7:0] n182_o;
  wire [5:0] n183_o;
  wire [7:0] n184_o;
  wire [4:0] n187_o;
  wire [7:0] n188_o;
  wire [7:0] n189_o;
  wire [7:0] n190_o;
  wire [3:0] n192_o;
  wire [6:0] n193_o;
  wire [4:0] n194_o;
  wire [6:0] n195_o;
  wire [6:0] n196_o;
  wire [7:0] n197_o;
  wire [4:0] n198_o;
  wire [1:0] n199_o;
  wire [4:0] n200_o;
  wire [4:0] n201_o;
  wire [5:0] n202_o;
  wire [7:0] n203_o;
  wire [5:0] n204_o;
  wire [7:0] n205_o;
  wire n206_o;
  wire n207_o;
  wire n293_o;
  wire [7:0] n296_o;
  wire [7:0] n298_o;
  wire n306_o;
  wire n308_o;
  wire [3:0] n310_o;
  wire [3:0] n312_o;
  wire n315_o;
  wire n327_o;
  wire n329_o;
  wire n330_o;
  wire n331_o;
  wire n332_o;
  wire n333_o;
  wire n334_o;
  wire n336_o;
  wire n338_o;
  wire n345_o;
  wire n347_o;
  wire n348_o;
  wire n349_o;
  wire n351_o;
  wire n353_o;
  wire n355_o;
  wire n362_o;
  wire [4:0] n364_o;
  wire [4:0] n366_o;
  wire [4:0] n373_o;
  wire [4:0] n375_o;
  wire [1:0] n376_o;
  wire n378_o;
  wire n379_o;
  wire n380_o;
  wire n381_o;
  wire n382_o;
  wire [4:0] n383_o;
  wire [3:0] n384_o;
  wire [3:0] n386_o;
  wire [4:0] n388_o;
  wire n391_o;
  wire [6:0] n399_o;
  wire [6:0] n401_o;
  wire n402_o;
  wire [6:0] n403_o;
  wire n405_o;
  wire n406_o;
  wire n410_o;
  wire n412_o;
  wire [3:0] n414_o;
  wire [3:0] n415_o;
  wire n417_o;
  wire [3:0] n419_o;
  wire n421_o;
  wire n436_o;
  wire n438_o;
  wire n439_o;
  wire n440_o;
  wire n441_o;
  wire n442_o;
  wire n444_o;
  wire n445_o;
  wire n446_o;
  wire n447_o;
  wire n449_o;
  wire n451_o;
  wire [6:0] n459_o;
  wire [7:0] n461_o;
  wire n462_o;
  wire n464_o;
  wire n467_o;
  wire n468_o;
  wire n469_o;
  wire n470_o;
  wire n471_o;
  wire n472_o;
  wire n475_o;
  wire n477_o;
  wire n478_o;
  wire n479_o;
  wire [4:0] n481_o;
  wire [4:0] n482_o;
  wire n484_o;
  wire [4:0] n485_o;
  wire n487_o;
  wire n501_o;
  wire n503_o;
  wire n506_o;
  wire n507_o;
  wire n508_o;
  wire n509_o;
  wire n510_o;
  wire n513_o;
  wire [1:0] n515_o;
  wire [2:0] n516_o;
  wire n517_o;
  wire n518_o;
  wire n519_o;
  wire n520_o;
  wire n521_o;
  wire n522_o;
  wire n525_o;
  wire n527_o;
  wire n528_o;
  wire n529_o;
  wire n531_o;
  wire n533_o;
  wire n534_o;
  wire n535_o;
  wire n536_o;
  wire n538_o;
  wire n539_o;
  wire n540_o;
  wire n541_o;
  wire n542_o;
  wire n544_o;
  wire n546_o;
  wire n548_o;
  wire n549_o;
  wire n550_o;
  wire n552_o;
  wire n554_o;
  wire n556_o;
  wire n558_o;
  wire n559_o;
  wire n560_o;
  wire n561_o;
  wire n562_o;
  wire n563_o;
  wire n564_o;
  wire n565_o;
  wire n567_o;
  wire n569_o;
  wire n577_o;
  wire n579_o;
  wire n580_o;
  wire n617_o;
  wire [13:0] n619_o;
  wire n620_o;
  wire n621_o;
  wire [13:0] n622_o;
  wire [13:0] n623_o;
  wire [13:0] n624_o;
  wire [13:0] n625_o;
  wire [13:0] n626_o;
  wire [13:0] n628_o;
  wire [13:0] n629_o;
  wire [13:0] n630_o;
  wire [1:0] n643_o;
  wire n645_o;
  wire n646_o;
  wire n647_o;
  wire n650_o;
  wire n652_o;
  wire [3:0] n655_o;
  wire [4:0] n656_o;
  wire [4:0] n657_o;
  wire n660_o;
  wire [2:0] n662_o;
  wire [3:0] n663_o;
  wire n664_o;
  wire n665_o;
  wire n666_o;
  wire n667_o;
  wire [5:0] n668_o;
  wire [7:0] n669_o;
  wire n672_o;
  wire n673_o;
  wire n686_o;
  wire n687_o;
  wire n688_o;
  wire [13:0] n689_o;
  wire n690_o;
  wire n691_o;
  wire n692_o;
  wire n693_o;
  wire n694_o;
  wire n695_o;
  wire n696_o;
  wire n697_o;
  wire n699_o;
  wire n700_o;
  wire n701_o;
  wire n703_o;
  wire n704_o;
  wire n707_o;
  wire n708_o;
  wire n723_o;
  wire n724_o;
  wire n727_o;
  wire n728_o;
  wire n729_o;
  wire n730_o;
  wire n733_o;
  wire n734_o;
  wire n735_o;
  wire n738_o;
  wire n739_o;
  wire n740_o;
  wire n742_o;
  wire n743_o;
  wire n744_o;
  wire n747_o;
  wire n748_o;
  wire n750_o;
  wire n751_o;
  wire n752_o;
  wire [4:0] n754_o;
  reg [4:0] n755_q;
  wire [7:0] n756_o;
  reg [7:0] n757_q;
  wire [7:0] n758_o;
  reg [7:0] n759_q;
  wire [7:0] n760_o;
  reg [7:0] n761_q;
  wire [3:0] n764_o;
  reg [3:0] n765_q;
  wire [6:0] n766_o;
  reg [6:0] n767_q;
  wire [4:0] n768_o;
  reg [4:0] n769_q;
  wire [6:0] n770_o;
  reg [6:0] n771_q;
  wire [6:0] n772_o;
  reg [6:0] n773_q;
  wire [7:0] n774_o;
  reg [7:0] n775_q;
  wire [4:0] n776_o;
  reg [4:0] n777_q;
  wire [1:0] n778_o;
  reg [1:0] n779_q;
  wire [4:0] n780_o;
  reg [4:0] n781_q;
  wire [4:0] n782_o;
  reg [4:0] n783_q;
  wire [5:0] n784_o;
  reg [5:0] n785_q;
  wire [7:0] n786_o;
  reg [7:0] n787_q;
  wire [5:0] n788_o;
  reg [5:0] n789_q;
  wire [7:0] n790_o;
  reg [7:0] n791_q;
  wire [5:0] n792_o;
  reg [5:0] n793_q;
  wire [7:0] n794_o;
  reg [7:0] n795_q;
  wire [7:0] n796_o;
  reg [7:0] n797_q;
  wire [3:0] n798_o;
  reg [3:0] n799_q;
  wire [6:0] n800_o;
  reg [6:0] n801_q;
  wire [4:0] n802_o;
  reg [4:0] n803_q;
  wire [3:0] n804_o;
  reg [3:0] n805_q;
  reg [4:0] n806_q;
  reg n807_q;
  reg n808_q;
  wire n809_o;
  reg n810_q;
  reg n811_q;
  wire n812_o;
  wire n813_o;
  wire n814_o;
  reg n815_q;
  wire n816_o;
  reg n817_q;
  reg n818_q;
  wire n819_o;
  reg n820_q;
  wire n821_o;
  reg n822_q;
  wire [13:0] n823_o;
  reg [13:0] n824_q;
  wire [3:0] n826_o;
  reg [3:0] n827_q;
  wire n836_o;
  reg n837_q;
  wire [13:0] n838_o;
  reg [13:0] n839_q;
  wire n840_o;
  reg n841_q;
  wire n842_o;
  reg n843_q;
  wire [2:0] n844_o;
  reg [2:0] n845_q;
  wire n846_o;
  reg n847_q;
  wire n848_o;
  reg n849_q;
  wire n850_o;
  reg n851_q;
  wire n852_o;
  reg n853_q;
  wire n854_o;
  reg n855_q;
  wire n856_o;
  reg n857_q;
  wire [4:0] n858_o;
  reg [4:0] n859_q;
  wire [6:0] n860_o;
  reg [6:0] n861_q;
  wire [7:0] n862_o;
  reg [7:0] n863_q;
  wire n864_o;
  reg n865_q;
  wire [3:0] n866_o;
  assign DO = n863_q;
  assign DO_VALID = n865_q;
  assign VSYNC = vs;
  assign HSYNC = hs;
  assign DE = de0;
  assign CURSOR = cursor0;
  assign MA = ma_i;
  assign RA = n657_o;
  assign test = n866_o;
  assign R1_ACTIVE = r01_h_displayed;
  assign H_DISPLAY_O = h_display;
  assign V_DISPLAY_O = v_display;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:88:8  */
  assign addr_reg = n755_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:91:8  */
  assign r00_h_total = n757_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:92:8  */
  assign r01_h_displayed = n759_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:93:8  */
  assign r02_h_sync_pos = n761_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:95:8  */
  assign r03_h_sync_width = n765_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:96:8  */
  assign r04_v_total = n767_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:97:8  */
  assign r05_v_total_adj = n769_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:98:8  */
  assign r06_v_displayed = n771_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:99:8  */
  assign r07_v_sync_pos = n773_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:100:8  */
  assign r08_interlace = n775_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:101:8  */
  assign r09_max_scanline_addr = n777_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:102:8  */
  assign r10_cursor_mode = n779_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:103:8  */
  assign r10_cursor_start = n781_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:104:8  */
  assign r11_cursor_end = n783_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:105:8  */
  assign r12_start_addr_h = n785_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:106:8  */
  assign r13_start_addr_l = n787_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:108:8  */
  assign r14_cursor_h = n789_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:109:8  */
  assign r15_cursor_l = n791_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:111:8  */
  assign r16_light_pen_h = n793_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:112:8  */
  assign r17_light_pen_l = n795_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:116:8  */
  assign h_counter = n797_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:118:8  */
  assign h_sync_counter = n799_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:120:8  */
  assign row_counter = n801_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:121:8  */
  assign row_counter_next = n399_o; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:123:8  */
  assign line_counter = n803_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:124:8  */
  assign line_counter_next = n373_o; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:126:8  */
  assign v_sync_counter = n805_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:128:8  */
  assign field_counter = n806_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:131:8  */
  assign h_display = n807_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:132:8  */
  assign hs = n808_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:133:8  */
  assign hs_started = n810_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:134:8  */
  assign v_display = n811_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:135:8  */
  assign vs = n472_o; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:136:8  */
  assign vs_hit = n406_o; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:137:8  */
  assign vs_hit_last = n815_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:138:8  */
  assign vs_started = n817_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:139:8  */
  assign vs_even = n818_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:140:8  */
  assign vs_odd = n820_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:141:8  */
  assign odd_field = n822_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:142:8  */
  assign ma_i = n824_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:144:8  */
  assign lpstb_sync = n827_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:145:8  */
  assign de0 = n724_o; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:148:8  */
  assign cursor0 = n696_o; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:151:8  */
  assign interlaced_video = n837_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:152:8  */
  assign max_scanline = n14_o; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:153:8  */
  assign adj_scanline = n34_o; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:154:8  */
  assign ma_row = n839_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:156:8  */
  assign in_adj = n841_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:157:8  */
  assign adj_in_progress = n843_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:158:8  */
  assign sol = n845_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:159:8  */
  assign eom_latched = n847_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:160:8  */
  assign eof_latched = n849_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:161:8  */
  assign first_scanline = n851_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:162:8  */
  assign extra_scanline = n853_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:163:8  */
  assign new_frame = n49_o; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:165:8  */
  assign r00_h_total_hit = n37_o; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:166:8  */
  assign max_scanline_hit = n26_o; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:173:8  */
  assign last_prev_line = n855_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:174:8  */
  assign hs_d1 = n857_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:175:8  */
  assign hsync_line_latch = n859_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:176:8  */
  assign hsync_row_latch = n861_q; // (signal)
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:192:43  */
  assign n13_o = r09_max_scanline_addr + 5'b00001;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:192:61  */
  assign n14_o = VGA ? n13_o : n21_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:193:42  */
  assign n15_o = r09_max_scanline_addr[4:1];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:193:55  */
  assign n17_o = {n15_o, 1'b0};
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:193:79  */
  assign n18_o = r08_interlace[1:0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:193:92  */
  assign n20_o = n18_o == 2'b11;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:192:99  */
  assign n21_o = n20_o ? n17_o : r09_max_scanline_addr;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:197:47  */
  assign n23_o = line_counter == max_scanline;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:197:82  */
  assign n24_o = ~adj_in_progress;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:197:62  */
  assign n25_o = n24_o & n23_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:197:29  */
  assign n26_o = n25_o ? 1'b1 : 1'b0;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:201:37  */
  assign n29_o = r05_v_total_adj + 5'b00010;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:201:59  */
  assign n30_o = r08_interlace[1:0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:201:72  */
  assign n32_o = n30_o == 2'b11;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:201:79  */
  assign n33_o = VGA & n32_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:201:41  */
  assign n34_o = n33_o ? n29_o : r05_v_total_adj;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:205:43  */
  assign n36_o = h_counter == r00_h_total;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:205:28  */
  assign n37_o = n36_o ? 1'b1 : 1'b0;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:208:49  */
  assign n40_o = eof_latched & r00_h_total_hit;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:208:89  */
  assign n41_o = r08_interlace[0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:208:93  */
  assign n42_o = ~n41_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:208:115  */
  assign n43_o = field_counter[0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:208:119  */
  assign n44_o = ~n43_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:208:99  */
  assign n45_o = n42_o | n44_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:208:125  */
  assign n46_o = n45_o | extra_scanline;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:208:149  */
  assign n47_o = n46_o | VGA;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:208:71  */
  assign n48_o = n47_o & n40_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:208:22  */
  assign n49_o = n48_o ? 1'b1 : 1'b0;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:218:19  */
  assign n53_o = ~nRESET;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:268:40  */
  assign n56_o = {2'b00, r14_cursor_h};
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:267:25  */
  assign n58_o = addr_reg == 5'b01110;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:270:25  */
  assign n60_o = addr_reg == 5'b01111;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:274:40  */
  assign n62_o = {2'b00, r16_light_pen_h};
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:273:25  */
  assign n64_o = addr_reg == 5'b10000;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:276:25  */
  assign n66_o = addr_reg == 5'b10001;
  assign n67_o = {n66_o, n64_o, n60_o, n58_o};
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:266:25  */
  always @*
    case (n67_o)
      4'b1000: n69_o = r17_light_pen_l;
      4'b0100: n69_o = n62_o;
      4'b0010: n69_o = r15_cursor_l;
      4'b0001: n69_o = n56_o;
      default: n69_o = 8'b00000000;
    endcase
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:266:25  */
  always @*
    case (n67_o)
      4'b1000: n75_o = 1'b1;
      4'b0100: n75_o = 1'b1;
      4'b0010: n75_o = 1'b1;
      4'b0001: n75_o = 1'b1;
      default: n75_o = 1'b0;
    endcase
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:265:21  */
  assign n77_o = RS ? n69_o : 8'b00000000;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:265:21  */
  assign n80_o = RS ? n75_o : 1'b0;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:285:27  */
  assign n82_o = ~RS;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:286:39  */
  assign n83_o = DI[4:0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:289:25  */
  assign n85_o = addr_reg == 5'b00000;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:291:25  */
  assign n87_o = addr_reg == 5'b00001;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:293:25  */
  assign n89_o = addr_reg == 5'b00010;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:297:60  */
  assign n91_o = DI[3:0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:295:25  */
  assign n93_o = addr_reg == 5'b00011;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:299:55  */
  assign n94_o = DI[6:0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:298:25  */
  assign n96_o = addr_reg == 5'b00100;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:301:59  */
  assign n97_o = DI[4:0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:300:25  */
  assign n99_o = addr_reg == 5'b00101;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:303:59  */
  assign n100_o = DI[6:0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:302:25  */
  assign n102_o = addr_reg == 5'b00110;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:305:58  */
  assign n103_o = DI[6:0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:304:25  */
  assign n105_o = addr_reg == 5'b00111;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:306:25  */
  assign n107_o = addr_reg == 5'b01000;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:309:65  */
  assign n108_o = DI[4:0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:308:25  */
  assign n110_o = addr_reg == 5'b01001;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:311:50  */
  assign n111_o = DI[6:5];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:312:60  */
  assign n112_o = DI[4:0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:310:25  */
  assign n114_o = addr_reg == 5'b01010;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:314:58  */
  assign n115_o = DI[4:0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:313:25  */
  assign n117_o = addr_reg == 5'b01011;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:316:60  */
  assign n118_o = DI[5:0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:315:25  */
  assign n120_o = addr_reg == 5'b01100;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:317:25  */
  assign n122_o = addr_reg == 5'b01101;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:320:56  */
  assign n123_o = DI[5:0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:319:25  */
  assign n125_o = addr_reg == 5'b01110;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:321:25  */
  assign n127_o = addr_reg == 5'b01111;
  assign n128_o = {n127_o, n125_o, n122_o, n120_o, n117_o, n114_o, n110_o, n107_o, n105_o, n102_o, n99_o, n96_o, n93_o, n89_o, n87_o, n85_o};
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:288:25  */
  always @*
    case (n128_o)
      16'b1000000000000000: n129_o = r00_h_total;
      16'b0100000000000000: n129_o = r00_h_total;
      16'b0010000000000000: n129_o = r00_h_total;
      16'b0001000000000000: n129_o = r00_h_total;
      16'b0000100000000000: n129_o = r00_h_total;
      16'b0000010000000000: n129_o = r00_h_total;
      16'b0000001000000000: n129_o = r00_h_total;
      16'b0000000100000000: n129_o = r00_h_total;
      16'b0000000010000000: n129_o = r00_h_total;
      16'b0000000001000000: n129_o = r00_h_total;
      16'b0000000000100000: n129_o = r00_h_total;
      16'b0000000000010000: n129_o = r00_h_total;
      16'b0000000000001000: n129_o = r00_h_total;
      16'b0000000000000100: n129_o = r00_h_total;
      16'b0000000000000010: n129_o = r00_h_total;
      16'b0000000000000001: n129_o = DI;
      default: n129_o = r00_h_total;
    endcase
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:288:25  */
  always @*
    case (n128_o)
      16'b1000000000000000: n130_o = r01_h_displayed;
      16'b0100000000000000: n130_o = r01_h_displayed;
      16'b0010000000000000: n130_o = r01_h_displayed;
      16'b0001000000000000: n130_o = r01_h_displayed;
      16'b0000100000000000: n130_o = r01_h_displayed;
      16'b0000010000000000: n130_o = r01_h_displayed;
      16'b0000001000000000: n130_o = r01_h_displayed;
      16'b0000000100000000: n130_o = r01_h_displayed;
      16'b0000000010000000: n130_o = r01_h_displayed;
      16'b0000000001000000: n130_o = r01_h_displayed;
      16'b0000000000100000: n130_o = r01_h_displayed;
      16'b0000000000010000: n130_o = r01_h_displayed;
      16'b0000000000001000: n130_o = r01_h_displayed;
      16'b0000000000000100: n130_o = r01_h_displayed;
      16'b0000000000000010: n130_o = DI;
      16'b0000000000000001: n130_o = r01_h_displayed;
      default: n130_o = r01_h_displayed;
    endcase
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:288:25  */
  always @*
    case (n128_o)
      16'b1000000000000000: n131_o = r02_h_sync_pos;
      16'b0100000000000000: n131_o = r02_h_sync_pos;
      16'b0010000000000000: n131_o = r02_h_sync_pos;
      16'b0001000000000000: n131_o = r02_h_sync_pos;
      16'b0000100000000000: n131_o = r02_h_sync_pos;
      16'b0000010000000000: n131_o = r02_h_sync_pos;
      16'b0000001000000000: n131_o = r02_h_sync_pos;
      16'b0000000100000000: n131_o = r02_h_sync_pos;
      16'b0000000010000000: n131_o = r02_h_sync_pos;
      16'b0000000001000000: n131_o = r02_h_sync_pos;
      16'b0000000000100000: n131_o = r02_h_sync_pos;
      16'b0000000000010000: n131_o = r02_h_sync_pos;
      16'b0000000000001000: n131_o = r02_h_sync_pos;
      16'b0000000000000100: n131_o = DI;
      16'b0000000000000010: n131_o = r02_h_sync_pos;
      16'b0000000000000001: n131_o = r02_h_sync_pos;
      default: n131_o = r02_h_sync_pos;
    endcase
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:288:25  */
  always @*
    case (n128_o)
      16'b1000000000000000: n133_o = r03_h_sync_width;
      16'b0100000000000000: n133_o = r03_h_sync_width;
      16'b0010000000000000: n133_o = r03_h_sync_width;
      16'b0001000000000000: n133_o = r03_h_sync_width;
      16'b0000100000000000: n133_o = r03_h_sync_width;
      16'b0000010000000000: n133_o = r03_h_sync_width;
      16'b0000001000000000: n133_o = r03_h_sync_width;
      16'b0000000100000000: n133_o = r03_h_sync_width;
      16'b0000000010000000: n133_o = r03_h_sync_width;
      16'b0000000001000000: n133_o = r03_h_sync_width;
      16'b0000000000100000: n133_o = r03_h_sync_width;
      16'b0000000000010000: n133_o = r03_h_sync_width;
      16'b0000000000001000: n133_o = n91_o;
      16'b0000000000000100: n133_o = r03_h_sync_width;
      16'b0000000000000010: n133_o = r03_h_sync_width;
      16'b0000000000000001: n133_o = r03_h_sync_width;
      default: n133_o = r03_h_sync_width;
    endcase
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:288:25  */
  always @*
    case (n128_o)
      16'b1000000000000000: n134_o = r04_v_total;
      16'b0100000000000000: n134_o = r04_v_total;
      16'b0010000000000000: n134_o = r04_v_total;
      16'b0001000000000000: n134_o = r04_v_total;
      16'b0000100000000000: n134_o = r04_v_total;
      16'b0000010000000000: n134_o = r04_v_total;
      16'b0000001000000000: n134_o = r04_v_total;
      16'b0000000100000000: n134_o = r04_v_total;
      16'b0000000010000000: n134_o = r04_v_total;
      16'b0000000001000000: n134_o = r04_v_total;
      16'b0000000000100000: n134_o = r04_v_total;
      16'b0000000000010000: n134_o = n94_o;
      16'b0000000000001000: n134_o = r04_v_total;
      16'b0000000000000100: n134_o = r04_v_total;
      16'b0000000000000010: n134_o = r04_v_total;
      16'b0000000000000001: n134_o = r04_v_total;
      default: n134_o = r04_v_total;
    endcase
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:288:25  */
  always @*
    case (n128_o)
      16'b1000000000000000: n135_o = r05_v_total_adj;
      16'b0100000000000000: n135_o = r05_v_total_adj;
      16'b0010000000000000: n135_o = r05_v_total_adj;
      16'b0001000000000000: n135_o = r05_v_total_adj;
      16'b0000100000000000: n135_o = r05_v_total_adj;
      16'b0000010000000000: n135_o = r05_v_total_adj;
      16'b0000001000000000: n135_o = r05_v_total_adj;
      16'b0000000100000000: n135_o = r05_v_total_adj;
      16'b0000000010000000: n135_o = r05_v_total_adj;
      16'b0000000001000000: n135_o = r05_v_total_adj;
      16'b0000000000100000: n135_o = n97_o;
      16'b0000000000010000: n135_o = r05_v_total_adj;
      16'b0000000000001000: n135_o = r05_v_total_adj;
      16'b0000000000000100: n135_o = r05_v_total_adj;
      16'b0000000000000010: n135_o = r05_v_total_adj;
      16'b0000000000000001: n135_o = r05_v_total_adj;
      default: n135_o = r05_v_total_adj;
    endcase
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:288:25  */
  always @*
    case (n128_o)
      16'b1000000000000000: n136_o = r06_v_displayed;
      16'b0100000000000000: n136_o = r06_v_displayed;
      16'b0010000000000000: n136_o = r06_v_displayed;
      16'b0001000000000000: n136_o = r06_v_displayed;
      16'b0000100000000000: n136_o = r06_v_displayed;
      16'b0000010000000000: n136_o = r06_v_displayed;
      16'b0000001000000000: n136_o = r06_v_displayed;
      16'b0000000100000000: n136_o = r06_v_displayed;
      16'b0000000010000000: n136_o = r06_v_displayed;
      16'b0000000001000000: n136_o = n100_o;
      16'b0000000000100000: n136_o = r06_v_displayed;
      16'b0000000000010000: n136_o = r06_v_displayed;
      16'b0000000000001000: n136_o = r06_v_displayed;
      16'b0000000000000100: n136_o = r06_v_displayed;
      16'b0000000000000010: n136_o = r06_v_displayed;
      16'b0000000000000001: n136_o = r06_v_displayed;
      default: n136_o = r06_v_displayed;
    endcase
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:288:25  */
  always @*
    case (n128_o)
      16'b1000000000000000: n137_o = r07_v_sync_pos;
      16'b0100000000000000: n137_o = r07_v_sync_pos;
      16'b0010000000000000: n137_o = r07_v_sync_pos;
      16'b0001000000000000: n137_o = r07_v_sync_pos;
      16'b0000100000000000: n137_o = r07_v_sync_pos;
      16'b0000010000000000: n137_o = r07_v_sync_pos;
      16'b0000001000000000: n137_o = r07_v_sync_pos;
      16'b0000000100000000: n137_o = r07_v_sync_pos;
      16'b0000000010000000: n137_o = n103_o;
      16'b0000000001000000: n137_o = r07_v_sync_pos;
      16'b0000000000100000: n137_o = r07_v_sync_pos;
      16'b0000000000010000: n137_o = r07_v_sync_pos;
      16'b0000000000001000: n137_o = r07_v_sync_pos;
      16'b0000000000000100: n137_o = r07_v_sync_pos;
      16'b0000000000000010: n137_o = r07_v_sync_pos;
      16'b0000000000000001: n137_o = r07_v_sync_pos;
      default: n137_o = r07_v_sync_pos;
    endcase
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:288:25  */
  always @*
    case (n128_o)
      16'b1000000000000000: n138_o = r08_interlace;
      16'b0100000000000000: n138_o = r08_interlace;
      16'b0010000000000000: n138_o = r08_interlace;
      16'b0001000000000000: n138_o = r08_interlace;
      16'b0000100000000000: n138_o = r08_interlace;
      16'b0000010000000000: n138_o = r08_interlace;
      16'b0000001000000000: n138_o = r08_interlace;
      16'b0000000100000000: n138_o = DI;
      16'b0000000010000000: n138_o = r08_interlace;
      16'b0000000001000000: n138_o = r08_interlace;
      16'b0000000000100000: n138_o = r08_interlace;
      16'b0000000000010000: n138_o = r08_interlace;
      16'b0000000000001000: n138_o = r08_interlace;
      16'b0000000000000100: n138_o = r08_interlace;
      16'b0000000000000010: n138_o = r08_interlace;
      16'b0000000000000001: n138_o = r08_interlace;
      default: n138_o = r08_interlace;
    endcase
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:288:25  */
  always @*
    case (n128_o)
      16'b1000000000000000: n139_o = r09_max_scanline_addr;
      16'b0100000000000000: n139_o = r09_max_scanline_addr;
      16'b0010000000000000: n139_o = r09_max_scanline_addr;
      16'b0001000000000000: n139_o = r09_max_scanline_addr;
      16'b0000100000000000: n139_o = r09_max_scanline_addr;
      16'b0000010000000000: n139_o = r09_max_scanline_addr;
      16'b0000001000000000: n139_o = n108_o;
      16'b0000000100000000: n139_o = r09_max_scanline_addr;
      16'b0000000010000000: n139_o = r09_max_scanline_addr;
      16'b0000000001000000: n139_o = r09_max_scanline_addr;
      16'b0000000000100000: n139_o = r09_max_scanline_addr;
      16'b0000000000010000: n139_o = r09_max_scanline_addr;
      16'b0000000000001000: n139_o = r09_max_scanline_addr;
      16'b0000000000000100: n139_o = r09_max_scanline_addr;
      16'b0000000000000010: n139_o = r09_max_scanline_addr;
      16'b0000000000000001: n139_o = r09_max_scanline_addr;
      default: n139_o = r09_max_scanline_addr;
    endcase
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:288:25  */
  always @*
    case (n128_o)
      16'b1000000000000000: n140_o = r10_cursor_mode;
      16'b0100000000000000: n140_o = r10_cursor_mode;
      16'b0010000000000000: n140_o = r10_cursor_mode;
      16'b0001000000000000: n140_o = r10_cursor_mode;
      16'b0000100000000000: n140_o = r10_cursor_mode;
      16'b0000010000000000: n140_o = n111_o;
      16'b0000001000000000: n140_o = r10_cursor_mode;
      16'b0000000100000000: n140_o = r10_cursor_mode;
      16'b0000000010000000: n140_o = r10_cursor_mode;
      16'b0000000001000000: n140_o = r10_cursor_mode;
      16'b0000000000100000: n140_o = r10_cursor_mode;
      16'b0000000000010000: n140_o = r10_cursor_mode;
      16'b0000000000001000: n140_o = r10_cursor_mode;
      16'b0000000000000100: n140_o = r10_cursor_mode;
      16'b0000000000000010: n140_o = r10_cursor_mode;
      16'b0000000000000001: n140_o = r10_cursor_mode;
      default: n140_o = r10_cursor_mode;
    endcase
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:288:25  */
  always @*
    case (n128_o)
      16'b1000000000000000: n141_o = r10_cursor_start;
      16'b0100000000000000: n141_o = r10_cursor_start;
      16'b0010000000000000: n141_o = r10_cursor_start;
      16'b0001000000000000: n141_o = r10_cursor_start;
      16'b0000100000000000: n141_o = r10_cursor_start;
      16'b0000010000000000: n141_o = n112_o;
      16'b0000001000000000: n141_o = r10_cursor_start;
      16'b0000000100000000: n141_o = r10_cursor_start;
      16'b0000000010000000: n141_o = r10_cursor_start;
      16'b0000000001000000: n141_o = r10_cursor_start;
      16'b0000000000100000: n141_o = r10_cursor_start;
      16'b0000000000010000: n141_o = r10_cursor_start;
      16'b0000000000001000: n141_o = r10_cursor_start;
      16'b0000000000000100: n141_o = r10_cursor_start;
      16'b0000000000000010: n141_o = r10_cursor_start;
      16'b0000000000000001: n141_o = r10_cursor_start;
      default: n141_o = r10_cursor_start;
    endcase
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:288:25  */
  always @*
    case (n128_o)
      16'b1000000000000000: n142_o = r11_cursor_end;
      16'b0100000000000000: n142_o = r11_cursor_end;
      16'b0010000000000000: n142_o = r11_cursor_end;
      16'b0001000000000000: n142_o = r11_cursor_end;
      16'b0000100000000000: n142_o = n115_o;
      16'b0000010000000000: n142_o = r11_cursor_end;
      16'b0000001000000000: n142_o = r11_cursor_end;
      16'b0000000100000000: n142_o = r11_cursor_end;
      16'b0000000010000000: n142_o = r11_cursor_end;
      16'b0000000001000000: n142_o = r11_cursor_end;
      16'b0000000000100000: n142_o = r11_cursor_end;
      16'b0000000000010000: n142_o = r11_cursor_end;
      16'b0000000000001000: n142_o = r11_cursor_end;
      16'b0000000000000100: n142_o = r11_cursor_end;
      16'b0000000000000010: n142_o = r11_cursor_end;
      16'b0000000000000001: n142_o = r11_cursor_end;
      default: n142_o = r11_cursor_end;
    endcase
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:288:25  */
  always @*
    case (n128_o)
      16'b1000000000000000: n143_o = r12_start_addr_h;
      16'b0100000000000000: n143_o = r12_start_addr_h;
      16'b0010000000000000: n143_o = r12_start_addr_h;
      16'b0001000000000000: n143_o = n118_o;
      16'b0000100000000000: n143_o = r12_start_addr_h;
      16'b0000010000000000: n143_o = r12_start_addr_h;
      16'b0000001000000000: n143_o = r12_start_addr_h;
      16'b0000000100000000: n143_o = r12_start_addr_h;
      16'b0000000010000000: n143_o = r12_start_addr_h;
      16'b0000000001000000: n143_o = r12_start_addr_h;
      16'b0000000000100000: n143_o = r12_start_addr_h;
      16'b0000000000010000: n143_o = r12_start_addr_h;
      16'b0000000000001000: n143_o = r12_start_addr_h;
      16'b0000000000000100: n143_o = r12_start_addr_h;
      16'b0000000000000010: n143_o = r12_start_addr_h;
      16'b0000000000000001: n143_o = r12_start_addr_h;
      default: n143_o = r12_start_addr_h;
    endcase
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:288:25  */
  always @*
    case (n128_o)
      16'b1000000000000000: n144_o = r13_start_addr_l;
      16'b0100000000000000: n144_o = r13_start_addr_l;
      16'b0010000000000000: n144_o = DI;
      16'b0001000000000000: n144_o = r13_start_addr_l;
      16'b0000100000000000: n144_o = r13_start_addr_l;
      16'b0000010000000000: n144_o = r13_start_addr_l;
      16'b0000001000000000: n144_o = r13_start_addr_l;
      16'b0000000100000000: n144_o = r13_start_addr_l;
      16'b0000000010000000: n144_o = r13_start_addr_l;
      16'b0000000001000000: n144_o = r13_start_addr_l;
      16'b0000000000100000: n144_o = r13_start_addr_l;
      16'b0000000000010000: n144_o = r13_start_addr_l;
      16'b0000000000001000: n144_o = r13_start_addr_l;
      16'b0000000000000100: n144_o = r13_start_addr_l;
      16'b0000000000000010: n144_o = r13_start_addr_l;
      16'b0000000000000001: n144_o = r13_start_addr_l;
      default: n144_o = r13_start_addr_l;
    endcase
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:288:25  */
  always @*
    case (n128_o)
      16'b1000000000000000: n145_o = r14_cursor_h;
      16'b0100000000000000: n145_o = n123_o;
      16'b0010000000000000: n145_o = r14_cursor_h;
      16'b0001000000000000: n145_o = r14_cursor_h;
      16'b0000100000000000: n145_o = r14_cursor_h;
      16'b0000010000000000: n145_o = r14_cursor_h;
      16'b0000001000000000: n145_o = r14_cursor_h;
      16'b0000000100000000: n145_o = r14_cursor_h;
      16'b0000000010000000: n145_o = r14_cursor_h;
      16'b0000000001000000: n145_o = r14_cursor_h;
      16'b0000000000100000: n145_o = r14_cursor_h;
      16'b0000000000010000: n145_o = r14_cursor_h;
      16'b0000000000001000: n145_o = r14_cursor_h;
      16'b0000000000000100: n145_o = r14_cursor_h;
      16'b0000000000000010: n145_o = r14_cursor_h;
      16'b0000000000000001: n145_o = r14_cursor_h;
      default: n145_o = r14_cursor_h;
    endcase
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:288:25  */
  always @*
    case (n128_o)
      16'b1000000000000000: n146_o = DI;
      16'b0100000000000000: n146_o = r15_cursor_l;
      16'b0010000000000000: n146_o = r15_cursor_l;
      16'b0001000000000000: n146_o = r15_cursor_l;
      16'b0000100000000000: n146_o = r15_cursor_l;
      16'b0000010000000000: n146_o = r15_cursor_l;
      16'b0000001000000000: n146_o = r15_cursor_l;
      16'b0000000100000000: n146_o = r15_cursor_l;
      16'b0000000010000000: n146_o = r15_cursor_l;
      16'b0000000001000000: n146_o = r15_cursor_l;
      16'b0000000000100000: n146_o = r15_cursor_l;
      16'b0000000000010000: n146_o = r15_cursor_l;
      16'b0000000000001000: n146_o = r15_cursor_l;
      16'b0000000000000100: n146_o = r15_cursor_l;
      16'b0000000000000010: n146_o = r15_cursor_l;
      16'b0000000000000001: n146_o = r15_cursor_l;
      default: n146_o = r15_cursor_l;
    endcase
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:283:17  */
  assign n147_o = n166_o ? n83_o : addr_reg;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:285:21  */
  assign n148_o = n82_o ? r00_h_total : n129_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:285:21  */
  assign n149_o = n82_o ? r01_h_displayed : n130_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:285:21  */
  assign n150_o = n82_o ? r02_h_sync_pos : n131_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:285:21  */
  assign n152_o = n82_o ? r03_h_sync_width : n133_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:285:21  */
  assign n153_o = n82_o ? r04_v_total : n134_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:285:21  */
  assign n154_o = n82_o ? r05_v_total_adj : n135_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:285:21  */
  assign n155_o = n82_o ? r06_v_displayed : n136_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:285:21  */
  assign n156_o = n82_o ? r07_v_sync_pos : n137_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:285:21  */
  assign n157_o = n82_o ? r08_interlace : n138_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:285:21  */
  assign n158_o = n82_o ? r09_max_scanline_addr : n139_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:285:21  */
  assign n159_o = n82_o ? r10_cursor_mode : n140_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:285:21  */
  assign n160_o = n82_o ? r10_cursor_start : n141_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:285:21  */
  assign n161_o = n82_o ? r11_cursor_end : n142_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:285:21  */
  assign n162_o = n82_o ? r12_start_addr_h : n143_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:285:21  */
  assign n163_o = n82_o ? r13_start_addr_l : n144_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:285:21  */
  assign n164_o = n82_o ? r14_cursor_h : n145_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:285:21  */
  assign n165_o = n82_o ? r15_cursor_l : n146_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:283:17  */
  assign n166_o = n82_o & CLKEN_CPU;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:283:17  */
  assign n167_o = CLKEN_CPU ? n148_o : r00_h_total;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:283:17  */
  assign n168_o = CLKEN_CPU ? n149_o : r01_h_displayed;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:283:17  */
  assign n169_o = CLKEN_CPU ? n150_o : r02_h_sync_pos;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:283:17  */
  assign n171_o = CLKEN_CPU ? n152_o : r03_h_sync_width;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:283:17  */
  assign n172_o = CLKEN_CPU ? n153_o : r04_v_total;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:283:17  */
  assign n173_o = CLKEN_CPU ? n154_o : r05_v_total_adj;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:283:17  */
  assign n174_o = CLKEN_CPU ? n155_o : r06_v_displayed;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:283:17  */
  assign n175_o = CLKEN_CPU ? n156_o : r07_v_sync_pos;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:283:17  */
  assign n176_o = CLKEN_CPU ? n157_o : r08_interlace;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:283:17  */
  assign n177_o = CLKEN_CPU ? n158_o : r09_max_scanline_addr;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:283:17  */
  assign n178_o = CLKEN_CPU ? n159_o : r10_cursor_mode;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:283:17  */
  assign n179_o = CLKEN_CPU ? n160_o : r10_cursor_start;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:283:17  */
  assign n180_o = CLKEN_CPU ? n161_o : r11_cursor_end;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:283:17  */
  assign n181_o = CLKEN_CPU ? n162_o : r12_start_addr_h;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:283:17  */
  assign n182_o = CLKEN_CPU ? n163_o : r13_start_addr_l;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:283:17  */
  assign n183_o = CLKEN_CPU ? n164_o : r14_cursor_h;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:283:17  */
  assign n184_o = CLKEN_CPU ? n165_o : r15_cursor_l;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:244:17  */
  assign n187_o = R_nW ? addr_reg : n147_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:244:17  */
  assign n188_o = R_nW ? r00_h_total : n167_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:244:17  */
  assign n189_o = R_nW ? r01_h_displayed : n168_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:244:17  */
  assign n190_o = R_nW ? r02_h_sync_pos : n169_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:244:17  */
  assign n192_o = R_nW ? r03_h_sync_width : n171_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:244:17  */
  assign n193_o = R_nW ? r04_v_total : n172_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:244:17  */
  assign n194_o = R_nW ? r05_v_total_adj : n173_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:244:17  */
  assign n195_o = R_nW ? r06_v_displayed : n174_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:244:17  */
  assign n196_o = R_nW ? r07_v_sync_pos : n175_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:244:17  */
  assign n197_o = R_nW ? r08_interlace : n176_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:244:17  */
  assign n198_o = R_nW ? r09_max_scanline_addr : n177_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:244:17  */
  assign n199_o = R_nW ? r10_cursor_mode : n178_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:244:17  */
  assign n200_o = R_nW ? r10_cursor_start : n179_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:244:17  */
  assign n201_o = R_nW ? r11_cursor_end : n180_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:244:17  */
  assign n202_o = R_nW ? r12_start_addr_h : n181_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:244:17  */
  assign n203_o = R_nW ? r13_start_addr_l : n182_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:244:17  */
  assign n204_o = R_nW ? r14_cursor_h : n183_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:244:17  */
  assign n205_o = R_nW ? r15_cursor_l : n184_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:243:13  */
  assign n206_o = R_nW & ENABLE;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:243:13  */
  assign n207_o = R_nW & ENABLE;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:341:19  */
  assign n293_o = ~nRESET;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:348:44  */
  assign n296_o = h_counter + 8'b00000001;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:345:17  */
  assign n298_o = r00_h_total_hit ? 8'b00000000 : n296_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:366:19  */
  assign n306_o = ~nRESET;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:371:23  */
  assign n308_o = ~hs;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:375:54  */
  assign n310_o = h_sync_counter + 4'b0001;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:371:17  */
  assign n312_o = n308_o ? 4'b0000 : n310_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:371:17  */
  assign n315_o = n308_o ? 1'b0 : 1'b1;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:397:19  */
  assign n327_o = ~nRESET;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:404:26  */
  assign n329_o = h_counter == r02_h_sync_pos;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:404:50  */
  assign n330_o = ~hs;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:404:43  */
  assign n331_o = n330_o & n329_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:406:28  */
  assign n332_o = hs_started & hs;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:406:68  */
  assign n333_o = h_sync_counter == r03_h_sync_width;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:406:49  */
  assign n334_o = n333_o & n332_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:406:13  */
  assign n336_o = n334_o ? 1'b0 : hs;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:404:13  */
  assign n338_o = n331_o ? 1'b1 : n336_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:422:19  */
  assign n345_o = ~nRESET;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:425:26  */
  assign n347_o = h_counter == r01_h_displayed;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:425:57  */
  assign n348_o = h_counter == r00_h_total;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:425:44  */
  assign n349_o = n347_o | n348_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:427:29  */
  assign n351_o = h_counter == 8'b00000000;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:427:13  */
  assign n353_o = n351_o ? 1'b1 : h_display;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:425:13  */
  assign n355_o = n349_o ? 1'b0 : n353_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:445:19  */
  assign n362_o = ~nRESET;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:451:17  */
  assign n364_o = r00_h_total_hit ? line_counter_next : line_counter;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:449:17  */
  assign n366_o = new_frame ? 5'b00000 : n364_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:458:42  */
  assign n373_o = max_scanline_hit ? 5'b00000 : n383_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:459:39  */
  assign n375_o = line_counter + 5'b00001;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:459:90  */
  assign n376_o = r08_interlace[1:0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:459:103  */
  assign n378_o = n376_o == 2'b11;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:459:118  */
  assign n379_o = ~VGA;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:459:110  */
  assign n380_o = n379_o & n378_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:459:73  */
  assign n381_o = ~n380_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:459:70  */
  assign n382_o = adj_in_progress | n381_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:458:70  */
  assign n383_o = n382_o ? n375_o : n388_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:460:38  */
  assign n384_o = line_counter[4:1];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:460:51  */
  assign n386_o = n384_o + 4'b0001;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:460:55  */
  assign n388_o = {n386_o, 1'b0};
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:466:19  */
  assign n391_o = ~nRESET;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:475:41  */
  assign n399_o = new_frame ? 7'b0000000 : n403_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:476:37  */
  assign n401_o = row_counter + 7'b0000001;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:476:68  */
  assign n402_o = max_scanline_hit & r00_h_total_hit;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:475:62  */
  assign n403_o = n402_o ? n401_o : row_counter;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:500:36  */
  assign n405_o = row_counter == r07_v_sync_pos;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:500:19  */
  assign n406_o = n405_o ? 1'b1 : 1'b0;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:516:19  */
  assign n410_o = ~nRESET;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:521:28  */
  assign n412_o = ~vs_even;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:525:54  */
  assign n414_o = v_sync_counter + 4'b0001;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:524:17  */
  assign n415_o = r00_h_total_hit ? n414_o : v_sync_counter;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:524:17  */
  assign n417_o = r00_h_total_hit ? 1'b1 : vs_started;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:521:17  */
  assign n419_o = n412_o ? 4'b0000 : n415_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:521:17  */
  assign n421_o = n412_o ? 1'b0 : n417_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:537:19  */
  assign n436_o = ~nRESET;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:540:45  */
  assign n438_o = ~vs_hit_last;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:540:29  */
  assign n439_o = n438_o & vs_hit;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:540:63  */
  assign n440_o = ~vs_even;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:540:51  */
  assign n441_o = n440_o & n439_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:545:33  */
  assign n442_o = vs_started & vs_even;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:545:73  */
  assign n444_o = v_sync_counter == 4'b0000;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:545:54  */
  assign n445_o = n444_o & n442_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:545:87  */
  assign n446_o = sol[0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:545:80  */
  assign n447_o = n446_o & n445_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:545:13  */
  assign n449_o = n447_o ? 1'b0 : vs_even;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:540:13  */
  assign n451_o = n441_o ? 1'b1 : n449_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:559:50  */
  assign n459_o = r00_h_total[7:1];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:559:37  */
  assign n461_o = {1'b0, n459_o};
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:559:30  */
  assign n462_o = h_counter == n461_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:558:13  */
  assign n464_o = n462_o & CLKEN;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:567:36  */
  assign n467_o = r08_interlace[0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:567:54  */
  assign n468_o = ~VGA;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:567:46  */
  assign n469_o = n468_o & n467_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:567:74  */
  assign n470_o = ~odd_field;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:567:60  */
  assign n471_o = n470_o & n469_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:567:18  */
  assign n472_o = n471_o ? vs_odd : vs_even;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:586:19  */
  assign n475_o = ~nRESET;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:595:43  */
  assign n477_o = field_counter[0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:596:31  */
  assign n478_o = row_counter == r06_v_displayed;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:596:49  */
  assign n479_o = v_display & n478_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:600:48  */
  assign n481_o = field_counter + 5'b00001;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:596:13  */
  assign n482_o = n479_o ? n481_o : field_counter;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:596:13  */
  assign n484_o = n479_o ? 1'b0 : v_display;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:591:13  */
  assign n485_o = first_scanline ? field_counter : n482_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:591:13  */
  assign n487_o = first_scanline ? 1'b1 : n484_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:613:19  */
  assign n501_o = ~nRESET;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:679:30  */
  assign n503_o = h_counter == r02_h_sync_pos;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:692:39  */
  assign n506_o = ~hs;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:692:32  */
  assign n507_o = n506_o & hs_d1;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:693:41  */
  assign n508_o = hsync_line_latch == max_scanline;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:693:76  */
  assign n509_o = hsync_row_latch == r04_v_total;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:693:56  */
  assign n510_o = n509_o & n508_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:693:21  */
  assign n513_o = n510_o ? 1'b1 : 1'b0;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:700:27  */
  assign n515_o = sol[1:0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:700:53  */
  assign n516_o = {n515_o, r00_h_total_hit};
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:707:26  */
  assign n517_o = sol[0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:712:63  */
  assign n518_o = row_counter == r04_v_total;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:712:47  */
  assign n519_o = n518_o & max_scanline_hit;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:712:96  */
  assign n520_o = ~last_prev_line;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:712:77  */
  assign n521_o = n520_o & n519_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:716:46  */
  assign n522_o = line_counter_next == adj_scanline;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:716:25  */
  assign n525_o = n522_o ? 1'b0 : 1'b1;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:716:25  */
  assign n527_o = n522_o ? 1'b1 : eof_latched;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:724:45  */
  assign n528_o = in_adj & eom_latched;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:726:46  */
  assign n529_o = line_counter_next == adj_scanline;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:724:21  */
  assign n531_o = n534_o ? 1'b0 : in_adj;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:724:21  */
  assign n533_o = n535_o ? 1'b1 : eof_latched;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:724:21  */
  assign n534_o = n529_o & n528_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:724:21  */
  assign n535_o = n529_o & n528_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:712:21  */
  assign n536_o = n521_o ? n525_o : n531_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:707:17  */
  assign n538_o = n541_o ? 1'b1 : eom_latched;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:712:21  */
  assign n539_o = n521_o ? n527_o : n533_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:707:17  */
  assign n540_o = n517_o ? n536_o : in_adj;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:707:17  */
  assign n541_o = n521_o & n517_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:707:17  */
  assign n542_o = n517_o ? n539_o : eof_latched;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:703:17  */
  assign n544_o = new_frame ? 1'b0 : n540_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:703:17  */
  assign n546_o = new_frame ? 1'b0 : n538_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:703:17  */
  assign n548_o = new_frame ? 1'b0 : n542_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:737:45  */
  assign n549_o = eom_latched & r00_h_total_hit;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:737:67  */
  assign n550_o = in_adj & n549_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:737:17  */
  assign n552_o = n550_o ? 1'b1 : adj_in_progress;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:735:17  */
  assign n554_o = new_frame ? 1'b0 : n552_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:744:17  */
  assign n556_o = r00_h_total_hit ? 1'b0 : first_scanline;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:742:17  */
  assign n558_o = new_frame ? 1'b1 : n556_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:749:42  */
  assign n559_o = eof_latched & r00_h_total_hit;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:749:81  */
  assign n560_o = r08_interlace[0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:749:64  */
  assign n561_o = n560_o & n559_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:749:108  */
  assign n562_o = field_counter[0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:749:91  */
  assign n563_o = n562_o & n561_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:749:137  */
  assign n564_o = ~extra_scanline;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:749:118  */
  assign n565_o = n564_o & n563_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:751:17  */
  assign n567_o = r00_h_total_hit ? 1'b0 : extra_scanline;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:749:17  */
  assign n569_o = n565_o ? 1'b1 : n567_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:626:13  */
  assign n577_o = n507_o & CLKEN;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:626:13  */
  assign n579_o = n503_o & CLKEN;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:626:13  */
  assign n580_o = n503_o & CLKEN;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:767:19  */
  assign n617_o = ~nRESET;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:774:48  */
  assign n619_o = {r12_start_addr_h, r13_start_addr_l};
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:775:33  */
  assign n620_o = h_counter == r01_h_displayed;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:775:51  */
  assign n621_o = max_scanline_hit & n620_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:779:52  */
  assign n622_o = {r12_start_addr_h, r13_start_addr_l};
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:778:21  */
  assign n623_o = eof_latched ? n622_o : ma_i;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:775:17  */
  assign n624_o = n621_o ? n623_o : ma_row;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:772:17  */
  assign n625_o = new_frame ? n619_o : n624_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:787:46  */
  assign n626_o = {r12_start_addr_h, r13_start_addr_l};
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:793:34  */
  assign n628_o = ma_i + 14'b00000000000001;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:788:17  */
  assign n629_o = r00_h_total_hit ? ma_row : n628_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:785:17  */
  assign n630_o = new_frame ? n626_o : n629_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:812:37  */
  assign n643_o = r08_interlace[1:0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:812:50  */
  assign n645_o = n643_o == 2'b11;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:812:65  */
  assign n646_o = ~VGA;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:812:57  */
  assign n647_o = n646_o & n645_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:812:21  */
  assign n650_o = n647_o ? 1'b1 : 1'b0;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:803:13  */
  assign n652_o = r00_h_total_hit & CLKEN;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:822:40  */
  assign n655_o = line_counter[4:1];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:822:54  */
  assign n656_o = {n655_o, odd_field};
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:822:66  */
  assign n657_o = interlaced_video ? n656_o : line_counter;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:836:19  */
  assign n660_o = ~nRESET;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:843:49  */
  assign n662_o = lpstb_sync[3:1];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:843:37  */
  assign n663_o = {LPSTB, n662_o};
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:845:30  */
  assign n664_o = lpstb_sync[1];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:845:54  */
  assign n665_o = lpstb_sync[0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:845:58  */
  assign n666_o = ~n665_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:845:40  */
  assign n667_o = n666_o & n664_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:846:44  */
  assign n668_o = ma_i[13:8];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:847:44  */
  assign n669_o = ma_i[7:0];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:841:13  */
  assign n672_o = n667_o & CLKEN;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:841:13  */
  assign n673_o = n667_o & CLKEN;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:859:35  */
  assign n686_o = ~h_display;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:859:54  */
  assign n687_o = ~v_display;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:859:41  */
  assign n688_o = n686_o | n687_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:859:84  */
  assign n689_o = {r14_cursor_h, r15_cursor_l};
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:859:68  */
  assign n690_o = ma_i != n689_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:859:60  */
  assign n691_o = n688_o | n690_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:859:115  */
  assign n692_o = $unsigned(line_counter) < $unsigned(r10_cursor_start);
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:859:99  */
  assign n693_o = n691_o | n692_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:859:150  */
  assign n694_o = $unsigned(line_counter) > $unsigned(r11_cursor_end);
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:859:134  */
  assign n695_o = n693_o | n694_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:859:20  */
  assign n696_o = n695_o ? 1'b0 : n700_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:860:29  */
  assign n697_o = field_counter[4];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:860:54  */
  assign n699_o = r10_cursor_mode == 2'b11;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:859:167  */
  assign n700_o = n699_o ? n697_o : n704_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:861:29  */
  assign n701_o = field_counter[3];
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:861:54  */
  assign n703_o = r10_cursor_mode == 2'b10;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:860:61  */
  assign n704_o = n703_o ? n701_o : n708_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:862:54  */
  assign n707_o = r10_cursor_mode == 2'b00;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:861:61  */
  assign n708_o = n707_o ? 1'b1 : 1'b0;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:885:37  */
  assign n723_o = v_display & h_display;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:885:16  */
  assign n724_o = n723_o ? 1'b1 : 1'b0;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:897:41  */
  assign n727_o = ENABLE & CLKEN_CPU;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:897:67  */
  assign n728_o = ~R_nW;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:897:58  */
  assign n729_o = n728_o & n727_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:897:20  */
  assign n730_o = n729_o ? 1'b1 : 1'b0;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:898:67  */
  assign n733_o = ~R_nW;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:898:58  */
  assign n734_o = n733_o & ENABLE;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:898:20  */
  assign n735_o = n734_o ? 1'b1 : 1'b0;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:899:41  */
  assign n738_o = ENABLE & CLKEN_CPU;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:899:67  */
  assign n739_o = ~R_nW;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:899:58  */
  assign n740_o = n739_o & n738_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:899:86  */
  assign n742_o = addr_reg == 5'b00000;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:899:73  */
  assign n743_o = n742_o & n740_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:899:20  */
  assign n744_o = n743_o ? 1'b1 : 1'b0;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:900:67  */
  assign n747_o = ~R_nW;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:900:58  */
  assign n748_o = n747_o & ENABLE;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:900:86  */
  assign n750_o = addr_reg == 5'b00000;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:900:73  */
  assign n751_o = n750_o & n748_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:900:20  */
  assign n752_o = n751_o ? 1'b1 : 1'b0;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  assign n754_o = ENABLE ? n187_o : addr_reg;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  always @(posedge CLOCK or posedge n53_o)
    if (n53_o)
      n755_q <= 5'b00000;
    else
      n755_q <= n754_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  assign n756_o = ENABLE ? n188_o : r00_h_total;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  always @(posedge CLOCK or posedge n53_o)
    if (n53_o)
      n757_q <= 8'b00000000;
    else
      n757_q <= n756_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  assign n758_o = ENABLE ? n189_o : r01_h_displayed;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  always @(posedge CLOCK or posedge n53_o)
    if (n53_o)
      n759_q <= 8'b00000000;
    else
      n759_q <= n758_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  assign n760_o = ENABLE ? n190_o : r02_h_sync_pos;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  always @(posedge CLOCK or posedge n53_o)
    if (n53_o)
      n761_q <= 8'b00000000;
    else
      n761_q <= n760_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  assign n764_o = ENABLE ? n192_o : r03_h_sync_width;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  always @(posedge CLOCK or posedge n53_o)
    if (n53_o)
      n765_q <= 4'b0000;
    else
      n765_q <= n764_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  assign n766_o = ENABLE ? n193_o : r04_v_total;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  always @(posedge CLOCK or posedge n53_o)
    if (n53_o)
      n767_q <= 7'b0000000;
    else
      n767_q <= n766_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  assign n768_o = ENABLE ? n194_o : r05_v_total_adj;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  always @(posedge CLOCK or posedge n53_o)
    if (n53_o)
      n769_q <= 5'b00000;
    else
      n769_q <= n768_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  assign n770_o = ENABLE ? n195_o : r06_v_displayed;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  always @(posedge CLOCK or posedge n53_o)
    if (n53_o)
      n771_q <= 7'b0000000;
    else
      n771_q <= n770_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  assign n772_o = ENABLE ? n196_o : r07_v_sync_pos;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  always @(posedge CLOCK or posedge n53_o)
    if (n53_o)
      n773_q <= 7'b0000000;
    else
      n773_q <= n772_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  assign n774_o = ENABLE ? n197_o : r08_interlace;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  always @(posedge CLOCK or posedge n53_o)
    if (n53_o)
      n775_q <= 8'b00000000;
    else
      n775_q <= n774_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  assign n776_o = ENABLE ? n198_o : r09_max_scanline_addr;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  always @(posedge CLOCK or posedge n53_o)
    if (n53_o)
      n777_q <= 5'b00000;
    else
      n777_q <= n776_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  assign n778_o = ENABLE ? n199_o : r10_cursor_mode;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  always @(posedge CLOCK or posedge n53_o)
    if (n53_o)
      n779_q <= 2'b00;
    else
      n779_q <= n778_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  assign n780_o = ENABLE ? n200_o : r10_cursor_start;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  always @(posedge CLOCK or posedge n53_o)
    if (n53_o)
      n781_q <= 5'b00000;
    else
      n781_q <= n780_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  assign n782_o = ENABLE ? n201_o : r11_cursor_end;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  always @(posedge CLOCK or posedge n53_o)
    if (n53_o)
      n783_q <= 5'b00000;
    else
      n783_q <= n782_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  assign n784_o = ENABLE ? n202_o : r12_start_addr_h;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  always @(posedge CLOCK or posedge n53_o)
    if (n53_o)
      n785_q <= 6'b000000;
    else
      n785_q <= n784_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  assign n786_o = ENABLE ? n203_o : r13_start_addr_l;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  always @(posedge CLOCK or posedge n53_o)
    if (n53_o)
      n787_q <= 8'b00000000;
    else
      n787_q <= n786_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  assign n788_o = ENABLE ? n204_o : r14_cursor_h;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  always @(posedge CLOCK or posedge n53_o)
    if (n53_o)
      n789_q <= 6'b000000;
    else
      n789_q <= n788_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  assign n790_o = ENABLE ? n205_o : r15_cursor_l;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  always @(posedge CLOCK or posedge n53_o)
    if (n53_o)
      n791_q <= 8'b00000000;
    else
      n791_q <= n790_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:840:9  */
  assign n792_o = n672_o ? n668_o : r16_light_pen_h;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:840:9  */
  always @(posedge CLOCK or posedge n660_o)
    if (n660_o)
      n793_q <= 6'b000000;
    else
      n793_q <= n792_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:840:9  */
  assign n794_o = n673_o ? n669_o : r17_light_pen_l;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:840:9  */
  always @(posedge CLOCK or posedge n660_o)
    if (n660_o)
      n795_q <= 8'b00000000;
    else
      n795_q <= n794_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:343:9  */
  assign n796_o = CLKEN ? n298_o : h_counter;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:343:9  */
  always @(posedge CLOCK or posedge n293_o)
    if (n293_o)
      n797_q <= 8'b00000000;
    else
      n797_q <= n796_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:369:9  */
  assign n798_o = CLKEN ? n312_o : h_sync_counter;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:369:9  */
  always @(posedge CLOCK or posedge n306_o)
    if (n306_o)
      n799_q <= 4'b0000;
    else
      n799_q <= n798_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:468:9  */
  assign n800_o = CLKEN ? row_counter_next : row_counter;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:468:9  */
  always @(posedge CLOCK or posedge n391_o)
    if (n391_o)
      n801_q <= 7'b0000000;
    else
      n801_q <= n800_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:447:9  */
  assign n802_o = CLKEN ? n366_o : line_counter;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:447:9  */
  always @(posedge CLOCK or posedge n362_o)
    if (n362_o)
      n803_q <= 5'b00000;
    else
      n803_q <= n802_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:519:9  */
  assign n804_o = CLKEN ? n419_o : v_sync_counter;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:519:9  */
  always @(posedge CLOCK or posedge n410_o)
    if (n410_o)
      n805_q <= 4'b0000;
    else
      n805_q <= n804_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:590:9  */
  always @(posedge CLOCK or posedge n475_o)
    if (n475_o)
      n806_q <= 5'b00000;
    else
      n806_q <= n485_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:424:9  */
  always @(posedge CLOCK or posedge n345_o)
    if (n345_o)
      n807_q <= 1'b0;
    else
      n807_q <= n355_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:399:9  */
  always @(posedge CLOCK or posedge n327_o)
    if (n327_o)
      n808_q <= 1'b0;
    else
      n808_q <= n338_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:369:9  */
  assign n809_o = CLKEN ? n315_o : hs_started;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:369:9  */
  always @(posedge CLOCK or posedge n306_o)
    if (n306_o)
      n810_q <= 1'b0;
    else
      n810_q <= n809_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:590:9  */
  always @(posedge CLOCK or posedge n475_o)
    if (n475_o)
      n811_q <= 1'b0;
    else
      n811_q <= n487_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:514:5  */
  assign n812_o = ~n410_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:514:5  */
  assign n813_o = CLKEN & n812_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:519:9  */
  assign n814_o = n813_o ? vs_hit : vs_hit_last;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:519:9  */
  always @(posedge CLOCK)
    n815_q <= n814_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:519:9  */
  assign n816_o = CLKEN ? n421_o : vs_started;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:519:9  */
  always @(posedge CLOCK or posedge n410_o)
    if (n410_o)
      n817_q <= 1'b0;
    else
      n817_q <= n816_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:539:9  */
  always @(posedge CLOCK or posedge n436_o)
    if (n436_o)
      n818_q <= 1'b0;
    else
      n818_q <= n451_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:557:9  */
  assign n819_o = n464_o ? vs_even : vs_odd;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:557:9  */
  always @(posedge CLOCK)
    n820_q <= n819_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:590:9  */
  assign n821_o = first_scanline ? n477_o : odd_field;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:590:9  */
  always @(posedge CLOCK or posedge n475_o)
    if (n475_o)
      n822_q <= 1'b0;
    else
      n822_q <= n821_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:770:9  */
  assign n823_o = CLKEN ? n630_o : ma_i;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:770:9  */
  always @(posedge CLOCK or posedge n617_o)
    if (n617_o)
      n824_q <= 14'b00000000000000;
    else
      n824_q <= n823_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:840:9  */
  assign n826_o = CLKEN ? n663_o : lpstb_sync;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:840:9  */
  always @(posedge CLOCK or posedge n660_o)
    if (n660_o)
      n827_q <= 4'b0000;
    else
      n827_q <= n826_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:802:9  */
  assign n836_o = n652_o ? n650_o : interlaced_video;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:802:9  */
  always @(posedge CLOCK)
    n837_q <= n836_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:770:9  */
  assign n838_o = CLKEN ? n625_o : ma_row;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:770:9  */
  always @(posedge CLOCK or posedge n617_o)
    if (n617_o)
      n839_q <= 14'b00000000000000;
    else
      n839_q <= n838_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:625:9  */
  assign n840_o = CLKEN ? n544_o : in_adj;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:625:9  */
  always @(posedge CLOCK or posedge n501_o)
    if (n501_o)
      n841_q <= 1'b0;
    else
      n841_q <= n840_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:625:9  */
  assign n842_o = CLKEN ? n554_o : adj_in_progress;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:625:9  */
  always @(posedge CLOCK or posedge n501_o)
    if (n501_o)
      n843_q <= 1'b0;
    else
      n843_q <= n842_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:625:9  */
  assign n844_o = CLKEN ? n516_o : sol;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:625:9  */
  always @(posedge CLOCK or posedge n501_o)
    if (n501_o)
      n845_q <= 3'b000;
    else
      n845_q <= n844_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:625:9  */
  assign n846_o = CLKEN ? n546_o : eom_latched;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:625:9  */
  always @(posedge CLOCK or posedge n501_o)
    if (n501_o)
      n847_q <= 1'b0;
    else
      n847_q <= n846_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:625:9  */
  assign n848_o = CLKEN ? n548_o : eof_latched;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:625:9  */
  always @(posedge CLOCK or posedge n501_o)
    if (n501_o)
      n849_q <= 1'b0;
    else
      n849_q <= n848_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:625:9  */
  assign n850_o = CLKEN ? n558_o : first_scanline;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:625:9  */
  always @(posedge CLOCK or posedge n501_o)
    if (n501_o)
      n851_q <= 1'b0;
    else
      n851_q <= n850_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:625:9  */
  assign n852_o = CLKEN ? n569_o : extra_scanline;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:625:9  */
  always @(posedge CLOCK or posedge n501_o)
    if (n501_o)
      n853_q <= 1'b0;
    else
      n853_q <= n852_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:625:9  */
  assign n854_o = n577_o ? n513_o : last_prev_line;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:625:9  */
  always @(posedge CLOCK or posedge n501_o)
    if (n501_o)
      n855_q <= 1'b0;
    else
      n855_q <= n854_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:625:9  */
  assign n856_o = CLKEN ? hs : hs_d1;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:625:9  */
  always @(posedge CLOCK or posedge n501_o)
    if (n501_o)
      n857_q <= 1'b0;
    else
      n857_q <= n856_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:625:9  */
  assign n858_o = n579_o ? line_counter : hsync_line_latch;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:625:9  */
  always @(posedge CLOCK or posedge n501_o)
    if (n501_o)
      n859_q <= 5'b00000;
    else
      n859_q <= n858_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:625:9  */
  assign n860_o = n580_o ? row_counter : hsync_row_latch;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:625:9  */
  always @(posedge CLOCK or posedge n501_o)
    if (n501_o)
      n861_q <= 7'b0000000;
    else
      n861_q <= n860_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  assign n862_o = n206_o ? n77_o : n863_q;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  always @(posedge CLOCK or posedge n53_o)
    if (n53_o)
      n863_q <= 8'b00000000;
    else
      n863_q <= n862_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  assign n864_o = n207_o ? n80_o : n865_q;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:242:9  */
  always @(posedge CLOCK or posedge n53_o)
    if (n53_o)
      n865_q <= 1'b0;
    else
      n865_q <= n864_o;
  /* /home/kevin/git/C900/rtl/mc6845/mc6845.vhd:218:9  */
  assign n866_o = {n752_o, n744_o, n735_o, n730_o};
endmodule

