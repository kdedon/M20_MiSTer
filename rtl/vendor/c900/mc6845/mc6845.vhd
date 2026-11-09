-- BBC Micro for Altera DE1
--
-- Copyright (c) 2022 David Banks (hoglet)
-- Copyright (c) 2011 Mike Stirling
--
-- All rights reserved
--
-- Redistribution and use in source and synthezised forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- * Redistributions of source code must retain the above copyright notice,
--   this list of conditions and the following disclaimer.
--
-- * Redistributions in synthesized form must reproduce the above copyright
--   notice, this list of conditions and the following disclaimer in the
--   documentation and/or other materials provided with the distribution.
--
-- * Neither the name of the author nor the names of other contributors may
--   be used to endorse or promote products derived from this software without
--   specific prior written agreement from the author.
--
-- * License is granted for non-commercial use only.  A fee may not be charged
--   for redistributions as source code or in synthesized/hardware form without
--   specific prior written agreement from the author.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
-- THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.
--
-- MC6845 CRTC
--
-- Synchronous implementation for FPGA
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mc6845 is
port (
    CLOCK     : in  std_logic;
    CLKEN     : in  std_logic;
    CLKEN_CPU : in  std_logic;
    nRESET    : in  std_logic;

    -- Bus interface
    ENABLE    : in  std_logic;
    R_nW      : in  std_logic;
    RS        : in  std_logic;
    DI        : in  std_logic_vector(7 downto 0);
    DO        : out std_logic_vector(7 downto 0);
    DO_VALID  : out std_logic;  -- Active when DO is driven (R14-R17 reads only)

    -- Display interface
    VSYNC     : out std_logic;
    HSYNC     : out std_logic;
    DE        : out std_logic;
    CURSOR    : out std_logic;
    LPSTB     : in  std_logic;

    VGA       : in  std_logic; -- Output Mode 7 as 624 line non-interlaced

    -- Memory interface
    MA        : out std_logic_vector(13 downto 0);
    RA        : out std_logic_vector(4 downto 0);
    test      : out std_logic_vector(3 downto 0);

    -- Exposed registers for auto-detection
    R1_ACTIVE : out std_logic_vector(7 downto 0);  -- R1 displayed columns

    -- Exposed display enable components (for direct blanking bypass)
    H_DISPLAY_O : out std_logic;  -- Horizontal display enable (active during displayed columns)
    V_DISPLAY_O : out std_logic   -- Vertical display enable (active during displayed rows)
    );
end entity;

architecture rtl of mc6845 is

-- Host-accessible registers
signal addr_reg               :   std_logic_vector(4 downto 0);   -- Currently addressed register

-- These are write-only
signal r00_h_total            : unsigned(7 downto 0);   -- Horizontal total, chars
signal r01_h_displayed        : unsigned(7 downto 0);   -- Horizontal active, chars
signal r02_h_sync_pos         : unsigned(7 downto 0);   -- Horizontal sync position, chars
signal r03_v_sync_width       : unsigned(3 downto 0);   -- Vertical sync width, scan lines (0=16 lines)
signal r03_h_sync_width       : unsigned(3 downto 0);   -- Horizontal sync width, chars (0=no sync)
signal r04_v_total            : unsigned(6 downto 0);   -- Vertical total, character rows
signal r05_v_total_adj        : unsigned(4 downto 0);   -- Vertical offset, scan lines
signal r06_v_displayed        : unsigned(6 downto 0);   -- Vertical active, character rows
signal r07_v_sync_pos         : unsigned(6 downto 0);   -- Vertical sync position, character rows
signal r08_interlace          : std_logic_vector(7 downto 0);
signal r09_max_scanline_addr  : unsigned(4 downto 0);
signal r10_cursor_mode        : std_logic_vector(1 downto 0);
signal r10_cursor_start       : unsigned(4 downto 0);   -- Cursor start, scan lines
signal r11_cursor_end         : unsigned(4 downto 0);   -- Cursor end, scan lines
signal r12_start_addr_h       : unsigned(5 downto 0);
signal r13_start_addr_l       : unsigned(7 downto 0);
-- These are read/write
signal r14_cursor_h           : unsigned(5 downto 0);
signal r15_cursor_l           : unsigned(7 downto 0);
-- These are read-only
signal r16_light_pen_h        : unsigned(5 downto 0);
signal r17_light_pen_l        : unsigned(7 downto 0);

-- Timing generation
-- Horizontal counter counts position on line
signal h_counter              : unsigned(7 downto 0);
-- HSYNC counter counts duration of sync pulse
signal h_sync_counter         : unsigned(3 downto 0);
-- Row counter counts current character row
signal row_counter            : unsigned(6 downto 0);
signal row_counter_next       : unsigned(6 downto 0);
-- Line counter counts current line within each character row (also used for vertical adjust)
signal line_counter           : unsigned(4 downto 0);
signal line_counter_next      : unsigned(4 downto 0);
-- VSYNC counter counts duration of sync pulse
signal v_sync_counter         : unsigned(3 downto 0);
-- Field counter counts number of complete fields for cursor flash
signal field_counter          : unsigned(4 downto 0);

-- Internal signals
signal h_display              : std_logic;
signal hs                     : std_logic;
signal hs_started             : std_logic;  -- tracks that sync counter has advanced past 0
signal v_display              : std_logic;
signal vs                     : std_logic;
signal vs_hit                 : std_logic;
signal vs_hit_last            : std_logic;
signal vs_started             : std_logic;  -- tracks that vsync counter has advanced past 0
signal vs_even                : std_logic;
signal vs_odd                 : std_logic;
signal odd_field              : std_logic; -- indicates the current field is an odd field, updated on counter wrap
signal ma_i                   : unsigned(13 downto 0);
signal cursor_i               : std_logic;
signal lpstb_sync             : std_logic_vector(3 downto 0);
signal de0                    : std_logic;
signal de1                    : std_logic;
signal de2                    : std_logic;
signal cursor0                : std_logic;
signal cursor1                : std_logic;
signal cursor2                : std_logic;
signal interlaced_video       : std_logic;
signal max_scanline           : unsigned(4 downto 0);
signal adj_scanline           : unsigned(4 downto 0);
signal ma_row                 : unsigned(13 downto 0);

signal in_adj                 : std_logic;
signal adj_in_progress        : std_logic;
signal sol                    : std_logic_vector(2 downto 0);
signal eom_latched            : std_logic;
signal eof_latched            : std_logic;
signal first_scanline         : std_logic;
signal extra_scanline         : std_logic;
signal new_frame              : std_logic;

signal r00_h_total_hit        : std_logic;
signal max_scanline_hit       : std_logic;

-- Type 2 (MC6845): "Last Previous Line" mechanism
-- At the last HSYNC position, if C4=R4 and C9=R9, the next line's
-- "Last Line" evaluation at C0=0 is suppressed. This prevents R4=0,R9=0
-- from creating 1-line frames. PETPeeve uses the RLAL technique (changing
-- R9 during HSYNC) to bypass this and achieve per-scanline MA control.
signal last_prev_line         : std_logic;
signal hs_d1                  : std_logic;  -- hs delayed by one CLKEN for falling edge detection
signal hsync_line_latch       : unsigned(4 downto 0);  -- line_counter latched at HSYNC start
signal hsync_row_latch        : unsigned(6 downto 0);  -- row_counter latched at HSYNC start

begin

    -- ===========================================================================
    --
    -- Common combinatorial logic
    --
    -- ===========================================================================

    -- TODO: Review the below two expressions, as the VGA mode criteria should really be the same

    -- Normally the max scan line is r09_max_scanline_addr, with two exceptions
    -- In VGA mode we add one so the mode 7 18 becomes 19 (giving 20 rows per character)
    -- In interlace sync + video mode we mask off the LSB

    max_scanline <= r09_max_scanline_addr + 1               when VGA = '1'                        else
                    r09_max_scanline_addr(4 downto 1) & '0' when r08_interlace(1 downto 0) = "11" else
                    r09_max_scanline_addr;

    -- In Type 0 CRTCs, C9 is used instead of C5, and max_scanline_hit is inhibited
    max_scanline_hit <= '1' when line_counter = max_scanline and adj_in_progress = '0' else '0';

    -- Normally the adjust scan line is r05_v_total_adj, with one exception
    -- In VGA Mode we add two so the Mode7 value of 2 becomes 4 (giving 31 * 20 + 4 = 624 lines)
    adj_scanline <= r05_v_total_adj + 2 when r08_interlace(1 downto 0) = "11" and VGA = '1'  else
                     r05_v_total_adj;

    -- Counter hits (only ones that are used in many places)
    r00_h_total_hit <= '1' when h_counter = r00_h_total  else '0';

    -- Indcates a new frame will start on the next clock tick.
    new_frame <= '1' when r00_h_total_hit = '1' and eof_latched = '1' and (r08_interlace(0) = '0' or field_counter(0) = '0' or extra_scanline = '1' or VGA = '1') else '0';

    -- ===========================================================================
    --
    -- Registers
    --
    -- ===========================================================================

    process(CLOCK,nRESET)
    begin
        if nRESET = '0' then
           -- Reset registers to defaults
            addr_reg <= (others => '0');
            r00_h_total <= (others => '0');
            r01_h_displayed <= (others => '0');
            r02_h_sync_pos <= (others => '0');
            r03_v_sync_width <= (others => '0');
            r03_h_sync_width <= (others => '0');
            r04_v_total <= (others => '0');
            r05_v_total_adj <= (others => '0');
            r06_v_displayed <= (others => '0');
            r07_v_sync_pos <= (others => '0');
            r08_interlace <= (others => '0');
            r09_max_scanline_addr <= (others => '0');
            r10_cursor_mode <= (others => '0');
            r10_cursor_start <= (others => '0');
            r11_cursor_end <= (others => '0');
            r12_start_addr_h <= (others => '0');
            r13_start_addr_l <= (others => '0');
            r14_cursor_h <= (others => '0');
            r15_cursor_l <= (others => '0');

            DO <= (others => '0');
            DO_VALID <= '0';
        elsif rising_edge(CLOCK) then
            if ENABLE = '1' then
                if R_nW = '1' then
                    -- Read
                    --
                    -- Type 2 (MC6845): Only R14-R17 are readable via RS=1.
                    -- All other reads leave the bus undriven (DO_VALID='0').
                    --
                    -- RS=0 (status register): The real MC6845 has no status
                    -- register. Per ACCC v1.7 §5.3 "Reading the Status Register":
                    --   "When reading the Status Register of a CRTC type 2,
                    --    the bus is not driven (active). The floating state of
                    --    the bus means that each read returns a random value,
                    --    which does not represent the status of the CRTC."
                    -- Ref: Amstrad CPC CRTC Compendium v1.7/1.8 (Serge Querne,
                    --       Logon System), https://shaker.logonsystem.eu/ACCC1.7-FR.pdf
                    --       English: https://www.cpcwiki.eu/imgs/4/4a/ACCC1.8-EN.pdf
                    --
                    -- The integration layer is responsible for pull-ups and any
                    -- parasitic VSYNC coupling on undriven reads. See crtc_or_not.sv.
                    --
                    DO <= (others => '0');
                    DO_VALID <= '0';
                    if RS = '1' then
                        case addr_reg is
                        when "01110" =>
                            DO <= "00" & std_logic_vector(r14_cursor_h);
                            DO_VALID <= '1';
                        when "01111" =>
                            DO <= std_logic_vector(r15_cursor_l);
                            DO_VALID <= '1';
                        when "10000" =>
                            DO <= "00" & std_logic_vector(r16_light_pen_h);
                            DO_VALID <= '1';
                        when "10001" =>
                            DO <= std_logic_vector(r17_light_pen_l);
                            DO_VALID <= '1';
                        when others =>
                            null;  -- not driven, DO_VALID stays '0'
                        end case;
                    end if;
                elsif CLKEN_CPU = '1' then
                    -- Write
                    if RS = '0' then
                        addr_reg <= DI(4 downto 0);
                    else
                        case addr_reg is
                        when "00000" =>
                            r00_h_total <= unsigned(DI);
                        when "00001" =>
                            r01_h_displayed <= unsigned(DI);
                        when "00010" =>
                            r02_h_sync_pos <= unsigned(DI);
                        when "00011" =>
                            r03_v_sync_width <= unsigned(DI(7 downto 4));
                            r03_h_sync_width <= unsigned(DI(3 downto 0));
                        when "00100" =>
                            r04_v_total <= unsigned(DI(6 downto 0));
                        when "00101" =>
                            r05_v_total_adj <= unsigned(DI(4 downto 0));
                        when "00110" =>
                            r06_v_displayed <= unsigned(DI(6 downto 0));
                        when "00111" =>
                            r07_v_sync_pos <= unsigned(DI(6 downto 0));
                        when "01000" =>
                            r08_interlace <= DI(7 downto 0);
                        when "01001" =>
                            r09_max_scanline_addr <= unsigned(DI(4 downto 0));
                        when "01010" =>
                            r10_cursor_mode <= DI(6 downto 5);
                            r10_cursor_start <= unsigned(DI(4 downto 0));
                        when "01011" =>
                            r11_cursor_end <= unsigned(DI(4 downto 0));
                        when "01100" =>
                            r12_start_addr_h <= unsigned(DI(5 downto 0));
                        when "01101" =>
                            r13_start_addr_l <= unsigned(DI(7 downto 0));
                        when "01110" =>
                            r14_cursor_h <= unsigned(DI(5 downto 0));
                        when "01111" =>
                            r15_cursor_l <= unsigned(DI(7 downto 0));
                        when others =>
                            null;
                        end case;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- ===========================================================================
    --
    -- HORIZONTAL TIMING
    --
    -- ===========================================================================

    -- Horizontal Counter
    process(CLOCK,nRESET)
    begin
        if nRESET = '0' then
            h_counter <= (others => '0');
        elsif rising_edge(CLOCK) then
            if CLKEN = '1' then
                if r00_h_total_hit = '1' then
                    h_counter <= (others => '0');
                else
                    h_counter <= h_counter + 1;
                end if;
            end if;
        end if;
    end process;

    -- Horizontal Sync Counter
    --
    -- Type 2 (MC6845): R3l sets HSYNC width:
    --       0 => 16 characters (counter wraps 4 bits)
    --       1 => hsync lasting 1 character
    --       ...
    --       15 => hsync lasting 15 characters
    --
    -- Changing R2 during HSYNC does not retrigger HSYNC
    -- Changing R3 during HSYNC does extend (or overflow) HSYNC
    process(CLOCK,nRESET)
    begin
        if nRESET = '0' then
            h_sync_counter <= (others => '0');
            hs_started <= '0';
        elsif rising_edge(CLOCK) then
            if CLKEN = '1' then
                if hs = '0' then
                    h_sync_counter <= x"0";
                    hs_started <= '0';
                else
                    h_sync_counter <= h_sync_counter + 1;
                    hs_started <= '1';
                end if;
            end if;
        end if;
    end process;

    -- Horizontal Sync
    --
    -- hs is modelled like a R/S flip-flop that reacts almost immediately
    -- to h_counter (one fast tick later)
    --
    -- Type 2: R3l=0 means 16-char HSYNC (not no HSYNC).
    -- The 4-bit sync counter counts 0,1,...,15,0 and HSYNC ends when
    -- counter matches R3l. With R3l=0, the counter wraps fully (16 chars).
    -- We check (counter + 1) = R3l to terminate one cycle after the match,
    -- which naturally handles R3l=0 (terminates when counter = 15, i.e.
    -- after 16 characters including the start).
    --
    -- Important: No clock enable is used here
    process(CLOCK,nRESET)
    begin
        if nRESET = '0' then
            hs <= '0';
        elsif rising_edge(CLOCK) then
            -- Type 2 (MC6845): R3l=0 means 16-char HSYNC.
            -- hs_started ensures we don't match counter=0=R3l at the start;
            -- the counter must have advanced past 0 first (wrapping back for R3l=0).
            -- Type 2 allows contiguous HSYNCs: set takes priority over clear.
            if h_counter = r02_h_sync_pos and hs = '0' then
                hs <= '1';
            elsif hs = '1' and hs_started = '1' and h_sync_counter = r03_h_sync_width then
                hs <= '0';
            end if;
        end if;
    end process;

    HSYNC <= hs; -- External HSYNC driven directly from internal signal

    -- Horizontal Display Enable
    --
    -- h_display is modelled like a R/S flip-flop that reacts almost immediately
    -- to h_counter (one fast tick later)
    --
    -- Important: No clock enable is used here
    process(CLOCK,nRESET)
    begin
        if nRESET = '0' then
            h_display <= '0';
        elsif rising_edge(CLOCK) then
            if h_counter = r01_h_displayed or h_counter = r00_h_total then
                h_display <= '0';
            elsif h_counter = 0 then
                h_display <= '1';
            end if;
        end if;
    end process;

    -- ===========================================================================
    --
    -- VERTICAL TIMING
    --
    -- ===========================================================================

    -- Vertical Scanline Counter (also used for vertical adjust)
    -- In interlaced sync + video mode it counts in steps of 2
    -- In interlaced sync mode and non-interlaced mode it counts in steps of 1
    -- In vertical adjust it also counts in steps of 1 regardless
    process(CLOCK,nRESET)
    begin
        if nRESET = '0' then
            line_counter <= (others => '0');
        elsif rising_edge(CLOCK) then
            if CLKEN = '1' then
                if new_frame = '1' then
                    line_counter <= (others => '0');
                elsif r00_h_total_hit = '1' then
                    line_counter <= line_counter_next;
                end if;
            end if;
        end if;
    end process;

    line_counter_next <= (others => '0') when max_scanline_hit = '1' else
                         line_counter + 1 when adj_in_progress = '1' or not(r08_interlace(1 downto 0) = "11" and VGA = '0') else
                         line_counter(4 downto 1) + 1 & '0';

    -- Vertical Row Counter

    process(CLOCK,nRESET)
    begin
        if nRESET = '0' then
            row_counter <= (others => '0');
        elsif rising_edge(CLOCK) then
            if CLKEN = '1' then
                row_counter <= row_counter_next;
            end if;
        end if;
    end process;

    row_counter_next <= (others => '0') when new_frame = '1' else
                        row_counter + 1 when r00_h_total_hit = '1' and max_scanline_hit = '1' else
                        row_counter;

    -- Vertical Sync
    --
    -- Note: r03_v_sync_width should have the following effect:
    --       0 => vsync lasting 16 lines
    --       1 => vsync lasting 1 line
    --       2 => vsync lasting 2 lines
    --       ...
    --       15 => vsync lasting 15 lines
    --
    -- Note: Measurements on a real beeb confirm:
    --       even vsync is aligned with the start of the active display
    --       odd vsync is delayed by exactly half a scan line
    --
    -- triggered immediately when C4=R7 (irrespective of h_counter)
    -- possible to generate several VSYNCs in a frame
    -- can only generate one VSYNC per row
    -- vsync counter increments on C0=0
    -- on vsync, vdisplay => 0
    -- R3=0 => 16 lines
    -- ??? what happens if R3 changes during vsync

    vs_hit <= '1' when row_counter = r07_v_sync_pos else '0';

    -- Vertical Sync Counter
    --
    -- Type 2 (MC6845): VSYNC is always 16 lines (R3h is ignored).
    -- Once triggered, VSYNC cannot be retriggered until the 16-line
    -- counter expires. This prevents VSYNC from being permanently stuck
    -- HIGH when frames are shorter than 16 lines (e.g., R4=$0A with
    -- R7=$01 gives 11-line frames, used by PETPeeve demo).
    --
    -- Follows the same pattern as the HSYNC counter: counter resets
    -- when vs_even='0', increments on line starts when vs_even='1',
    -- and vs_started prevents the counter=0 end-condition from matching
    -- immediately after reset.
    process(CLOCK,nRESET)
    begin
        if nRESET = '0' then
            v_sync_counter <= (others => '0');
            vs_started <= '0';
        elsif rising_edge(CLOCK) then
            if CLKEN = '1' then
                if vs_even = '0' then
                    v_sync_counter <= x"0";
                    vs_started <= '0';
                elsif r00_h_total_hit = '1' then
                    v_sync_counter <= v_sync_counter + 1;
                    vs_started <= '1';
                end if;
                vs_hit_last <= vs_hit;
            end if;
        end if;
    end process;

    -- vs_even is modelled like a R/S flip-flop
    -- Important: No clock enable is used here (reacts immediately like hs)
    process(CLOCK,nRESET)
    begin
        if nRESET = '0' then
            vs_even <= '0';
        elsif rising_edge(CLOCK) then
            if vs_hit = '1' and vs_hit_last = '0' and vs_even = '0' then
                -- Trigger VSYNC only when not already active (Type 2: non-retriggerable)
                -- TODO: Type 2 Ghost VSYNC (suppress pin during HSYNC) needs
                -- careful handling for 40-col PETs where HSYNC wraps through C0=0.
                vs_even <= '1';
            elsif vs_even = '1' and vs_started = '1' and v_sync_counter = x"0" and sol(0) = '1' then
                -- Type 2 (MC6845): VSYNC is always 16 lines (ignore R3h)
                -- vs_started ensures we don't match counter=0 at the start;
                -- the counter must have advanced past 0 first (wrapping back).
                vs_even <= '0';
            end if;
        end if;
    end process;

    -- Generate an odd vsync that is delayed by half a line
    process(CLOCK)
    begin
        if rising_edge(CLOCK) then
            if CLKEN = '1' then
                if h_counter = ("0" & r00_h_total(7 downto 1)) then
                    vs_odd <= vs_even;
                end if;
            end if;
        end if;
    end process;

    -- Select between vs_odd and vs_even based on interlace state
    vs <= vs_odd when r08_interlace(0) = '1' and VGA = '0' and odd_field = '0' else vs_even;
    VSYNC <= vs; -- External VSYNC driven directly from internal signal

    -- Vertical Display Enable
    --
    -- JSBEEB contains this comment concerning R6 hit:
    --    The Hitachi 6845 will notice this equality at any character,
    --    including in the middle of a scanline.
    --
    -- Surprisingly, the odd/even flag and field counter are updated based on R6
    -- i.e. Both cursor blink and interlace cease if R6 > R4.
    -- https://github.com/mattgodbolt/jsbeeb/blob/main/video.js#L641
    --
    -- In interlaced modes, the LSB of the field counter indicates the odd/even field type
    -- which is latched in odd_field so it's stable for the whole of the next frame.
    --
    -- Important: No clock enable is used here
    process(CLOCK,nRESET)
    begin
        if nRESET = '0' then
            v_display <= '0';
            field_counter <= (others => '0');
            odd_field <= '0';
        elsif rising_edge(CLOCK) then
            if first_scanline = '1' then
                -- Enable the display when C4 = C9 = 0
                v_display <= '1';
                -- Latch odd field so it's stable for the whole field
                odd_field <= field_counter(0);
            elsif row_counter = r06_v_displayed and v_display = '1' then
                -- Disable the display when C4 = R6, irrespective of C9
                v_display <= '0';
                -- Increment field counter
                field_counter <= field_counter + 1;
            end if;
        end if;
    end process;

    -- ===========================================================================
    --
    -- End of frame logic
    --
    -- ===========================================================================

    process(CLOCK,nRESET)
    begin
        if nRESET = '0' then
            sol <= (others => '0');
            in_adj <= '0';
            adj_in_progress <= '0';
            eom_latched <= '0';
            eof_latched <= '0';
            first_scanline <= '0';
            extra_scanline <= '0';
            last_prev_line <= '0';
            hs_d1 <= '0';
            hsync_line_latch <= (others => '0');
            hsync_row_latch <= (others => '0');
        elsif rising_edge(CLOCK) then
            if CLKEN = '1' then

                -- TODO: Confirm extactly when end of main (EOM) is latched
                --
                -- i.e. Is EOM latched on entering C0=1 or on exiting C0=1
                --
                -- RichTW says:
                --
                --     One character after the beginning of a new scanline (normally when C0 is
                --     exactly 1), the CTRC latches the "end of frame pending" signal.  After this
                --     moment, the CRTC is committed to ending the current frame, regardless of
                --     changes to R4 or R9 after that.
                --
                --     Two characters after the beginning of a new scanline (normally when C0 is
                --     exactly 2 (!)), the CRTC decides whether it needs to enter vertical adjust as
                --     part of the end of frame sequence.  In other words, if R5=0, but you then
                --     change it any time after C0=2 when C9=R9 and C4=R4, it won't get noticed, and
                --     there will be no vertical adjust.  In the case where R0=1, it doesn't get to
                --     do that check by the supposed end of frame, so an extra scanline occurs with
                --     C9=0 and C4=R4+1, and it will then see that no vertical adjust is due and
                --     finish the frame at the end of the next scanline.

                -- https://www.cpcwiki.eu/forum/programming/crtc-detailed-operation/msg180078/#msg180078
                --
                -- Amstrad CRTC Compendion says:
                --
                --     When C0=0, the CRTC evaluates if C0=R9 and
                --     C4=R4 to determine if it is on the bottom line
                --     of the screen. Ir no longer repeats this on
                --     other values of C0.
                --
                -- https://www.cpcwiki.eu/forum/news-events/release-of-amstrad-cpc-crtc-compendium-and-amazing-demo-rev-2021/msg209689/#msg209689
                --
                -- From this, I would say it's on the transition of C0=0 => C0=1
                --
                -- Looking at the beebjit code, it seems latching end-of-main, vertical-adjust and
                -- end-of-frame happen over three successive cycles.

                -- Type 2 (MC6845): All end-of-frame evaluation happens at C0=0.
                -- The CPC Wiki states: "When C0=0, the CRTC evaluates if C9=R9
                -- and C4=R4 to determine if it is on the bottom line of the
                -- screen. It no longer repeats this on other values of C0."
                --
                -- We use sol(0) as the C0=0 marker, and evaluate eom, adj,
                -- and eof in a single cycle using combinatorial lookahead.

                -- Type 2: "Last Previous Line" mechanism
                -- Latch vertical counters at HSYNC start position (h_counter=R2).
                -- These latched values are used at HSYNC-end to evaluate whether
                -- the current line is a "last line" for the NEXT line's suppression.
                -- Latching at HSYNC start avoids issues when HSYNC wraps past the
                -- line end (40-column PETs), where the counters at HSYNC-end would
                -- reflect the new line's values.
                if h_counter = r02_h_sync_pos then
                    hsync_line_latch <= line_counter;
                    hsync_row_latch <= row_counter;
                end if;

                -- Track hs for falling edge detection in the CLKEN domain
                hs_d1 <= hs;

                -- Evaluate "Last Previous Line" at HSYNC falling edge.
                -- Uses latched counters (from HSYNC start) compared against
                -- current register values (which may have been changed during HSYNC
                -- by the RLAL technique: changing R9 during HSYNC prevents
                -- last_prev_line from being set).
                if hs_d1 = '1' and hs = '0' then
                    if hsync_line_latch = max_scanline and hsync_row_latch = r04_v_total then
                        last_prev_line <= '1';
                    else
                        last_prev_line <= '0';
                    end if;
                end if;

                sol <= sol(sol'length - 2 downto 0) & r00_h_total_hit;

                -- At C0=0: evaluate end-of-main, vertical adjust, and end-of-frame
                if new_frame = '1' then
                    eom_latched <= '0';
                    in_adj <= '0';
                    eof_latched <= '0';
                elsif sol(0) = '1' then
                    -- Type 2: "Last Previous Line" exception - if the previous line
                    -- was detected as a "last line" at its HSYNC-end, suppress the
                    -- "Last Line" evaluation on this line. Once armed on Type 2,
                    -- "Last Line" cannot be disarmed.
                    if max_scanline_hit = '1' and row_counter = r04_v_total and last_prev_line = '0' then
                        -- End of main detected
                        eom_latched <= '1';
                        -- Immediately decide: vertical adjust needed?
                        if line_counter_next = adj_scanline then
                            -- No adjust needed (R5=0 or already done)
                            in_adj <= '0';
                            eof_latched <= '1';
                        else
                            -- Need vertical adjust
                            in_adj <= '1';
                        end if;
                    elsif eom_latched = '1' and in_adj = '1' then
                        -- During vertical adjust: check if adjust is done
                        if line_counter_next = adj_scanline then
                            in_adj <= '0';
                            eof_latched <= '1';
                        end if;
                    end if;
                end if;

                -- adj_in_progress tracks that we're in the adjust phase,
                -- used to force line counter increment to 1 and disable max_scanline_hit
                if new_frame = '1' then
                    adj_in_progress <= '0';
                elsif r00_h_total_hit = '1' and eom_latched = '1' and in_adj = '1' then
                    adj_in_progress <= '1';
                end if;

                -- First_scanline is active for the first scanline of the field; this affects only the R06 hit logic
                if new_frame = '1' then
                    first_scanline <= '1';
                elsif r00_h_total_hit = '1' then
                    first_scanline <= '0';
                end if;

                -- Extra_scanline records that an extra scanline was added to the field
                if r00_h_total_hit = '1' and eof_latched = '1' and r08_interlace(0) = '1' and field_counter(0) = '1' and extra_scanline = '0' then
                    extra_scanline <= '1';
                elsif r00_h_total_hit = '1' then
                    extra_scanline <= '0';
                end if;

            end if;
        end if;
    end process;

    -- ===========================================================================
    --
    -- Memory Address Generation
    --
    -- ===========================================================================

    process(CLOCK,nRESET)
    begin
        if nRESET = '0' then
            ma_row <= (others => '0');
            ma_i <= (others => '0');
        elsif rising_edge(CLOCK) then
            if CLKEN = '1' then
                if new_frame = '1' then
                    -- At start of frame the row start address is loaded from r12/13
                    ma_row <= r12_start_addr_h & r13_start_addr_l;
                elsif h_counter = r01_h_displayed and max_scanline_hit = '1' then
                    -- Type 2 (MC6845): on the last raster line of the frame,
                    -- MA' captures R12/R13 instead of MA (current address).
                    if eof_latched = '1' then
                        ma_row <= r12_start_addr_h & r13_start_addr_l;
                    else
                        -- Normal: row start address loaded with address of next row
                        ma_row <= ma_i;
                    end if;
                end if;
                if new_frame = '1' then
                    -- At start of frame the memory address is loaded from r12/13
                    ma_i <= r12_start_addr_h & r13_start_addr_l;
                elsif r00_h_total_hit = '1' then
                    -- At start of each line the memory addess is reset back to the row start address
                    ma_i <= ma_row;
                else
                    -- During the line the memory address is incremented
                    ma_i <= ma_i + 1;
                end if;
            end if;
        end if;
    end process;

    -- Address generation
    process(CLOCK,nRESET)
    begin
        if rising_edge(CLOCK) then
            if CLKEN = '1' then
                -- On the Real 6845 you don't see glitches on RA0 when writing r08
                -- so mimic this by latching the relevant r08 state once per line.
                -- This is probably done differently on the real hardware. I suspect
                -- the replacement of line_counter(0) with odd_field is done
                -- upstream as part of the line counter logic, and then when comparing
                -- to the max scanline, the LSB is masked off. I had a got at implementing
                -- this, but it got messy.
                if r00_h_total_hit = '1' then
                    if r08_interlace(1 downto 0) = "11" and VGA = '0' then
                        interlaced_video <= '1';
                    else
                        interlaced_video <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    RA <= std_logic_vector(line_counter(4 downto 1)) & odd_field when interlaced_video = '1' else
          std_logic_vector(line_counter);

    MA <= std_logic_vector(ma_i);


    -- ===========================================================================
    --
    -- Light pen
    --
    -- ===========================================================================

    process(CLOCK,nRESET)
    begin
        if nRESET = '0' then
            lpstb_sync <= (others => '0');
            r16_light_pen_h <= (others => '0');
            r17_light_pen_l <= (others => '0');
        elsif rising_edge(CLOCK) then
            if CLKEN = '1' then
                -- Synchronise light-pen strobe input
                lpstb_sync <= LPSTB & lpstb_sync(lpstb_sync'length - 1 downto 1);
                -- Capture memory address on rising edge
                if lpstb_sync(1) = '1' and lpstb_sync(0) = '0' then
                    r16_light_pen_h <= ma_i(13 downto 8);
                    r17_light_pen_l <= ma_i(7 downto 0);
                end if;
            end if;
        end if;
    end process;

    -- ===========================================================================
    --
    -- Cursor control
    --
    -- ===========================================================================

    cursor0 <= '0' when h_display = '0' or v_display = '0' or ma_i /= r14_cursor_h & r15_cursor_l or line_counter < r10_cursor_start or line_counter > r11_cursor_end else
               field_counter(4) when r10_cursor_mode = "11" else
               field_counter(3) when r10_cursor_mode = "10" else
               '1'              when r10_cursor_mode = "00" else
               '0';

    -- ===========================================================================
    --
    -- Skew (of cursor and display enable)
    --
    -- ===========================================================================

    process(CLOCK,nRESET)
    begin
        if rising_edge(CLOCK) then
            if CLKEN = '1' then
                de1     <= de0;
                de2     <= de1;
                cursor1 <= cursor0;
                cursor2 <= cursor1;
            end if;
        end if;
    end process;

    -- Type 2 (MC6845): R8 bits 7:2 are ignored (no skew support).
    -- Only bits 1:0 (interlace mode) are meaningful.
    de0 <= '1' when h_display = '1' and v_display = '1' else '0';

    DE <= de0;

    CURSOR <= cursor0;

    -- ===========================================================================
    --
    -- Test
    --
    -- ===========================================================================

    test(0) <= '1' when CLKEN_CPU = '1' and ENABLE = '1' and R_nW = '0' else '0';
    test(1) <= '1' when                     ENABLE = '1' and R_nW = '0' else '0';
    test(2) <= '1' when CLKEN_CPU = '1' and ENABLE = '1' and R_nW = '0' and addr_reg = "00000" else '0';
    test(3) <= '1' when                     ENABLE = '1' and R_nW = '0' and addr_reg = "00000" else '0';

    R1_ACTIVE <= std_logic_vector(r01_h_displayed);

    -- Expose individual display enable components for direct blanking
    H_DISPLAY_O <= h_display;
    V_DISPLAY_O <= v_display;

end architecture;
