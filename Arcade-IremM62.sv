//============================================================================
//  Arcade: Irem62
//
//  Port to MiSTer
//  Copyright (C) 2017 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        VGA_CLK,

	//Multiple resolutions are supported using different VGA_CE rates.
	//Must be based on CLK_VIDEO
	output        VGA_CE,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,

	//Base video clock. Usually equals to CLK_SYS.
	output        HDMI_CLK,

	//Multiple resolutions are supported using different HDMI_CE rates.
	//Must be based on CLK_VIDEO
	output        HDMI_CE,

	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_DE,   // = ~(VBlank | HBlank)
	output  [1:0] HDMI_SL,   // scanlines fx

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] HDMI_ARX,
	output  [7:0] HDMI_ARY,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,    // 1 - signed audio samples, 0 - unsigned

	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE, 
	
	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT
);

assign VGA_F1    = 0;
assign USER_OUT  = '1;
assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign HDMI_ARX = status[1] ? 8'd16 : (status[2] | landscape) ? 8'd4 : 8'd3;
assign HDMI_ARY = status[1] ? 8'd9  : (status[2] | landscape) ? 8'd3 : 8'd4;


`include "build_id.v" 
localparam CONF_STR = {
	"A.IREMM62;;",
	"H0O1,Aspect Ratio,Original,Wide;",
	"H1H0O2,Orientation,Vert,Horz;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"DIP;",
	"-;",
	"R0,Reset;",
	"J1,Dig Left,Dig Right,Start 1P,Start 2P,Coin;",
	"jn,A,B,Start,Select,R;",
	"V,v",`BUILD_DATE
};


reg        oneplayer;

reg [7:0] core_mod = 0;

always @(posedge clk_sys) begin
        if (ioctl_wr & (ioctl_index==1)) core_mod <= ioctl_dout;
end

reg landscape;
reg ccw;

always @(*) begin
 // oneplayer = 1;
  landscape = 1;
  ccw = 0;
  case (core_mod)
//  8'h3: oneplayer = 0; // LDRUN4
  8'h6: 
	begin
 // BATTROAD
        landscape = 0;
        end
	8'hB: begin
	   // YOUJYUDN
           landscape = 0;
	   ccw = 1;
     end
  default: ;
  endcase
end

////////////////////   CLOCKS   ///////////////////

wire clk_sys, clk_vid, clk_aud, clk_mem;

wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_mem),
	.outclk_1(clk_vid),
	.outclk_2(clk_sys),
	.outclk_3(clk_aud),
	.locked(pll_locked)
);

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;

wire        ioctl_download_2;
wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

wire [10:0] ps2_key;

wire [15:0] joy1 = joy1a;
wire [15:0] joy2 = joy2a;
wire [15:0] joy1a;
wire [15:0] joy2a;

wire [21:0] gamma_bus;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),
	.status_menumask({landscape,direct_video}),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),

	.ioctl_download(ioctl_download_2),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index),

	.joystick_0(joy1a),
	.joystick_1(joy2a),
	.ps2_key(ps2_key)
);

assign ioctl_download = ioctl_download_2 & !ioctl_index;

reg [7:0] sw[8];
always @(posedge clk_sys) if (ioctl_wr && (ioctl_index==254) && !ioctl_addr[24:3]) sw[ioctl_addr[2:0]] <= ioctl_dout;

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];
	
	if(old_state != ps2_key[10]) begin
		casex(code)
			'hX75: btn_up          <= pressed; // up
			'hX72: btn_down        <= pressed; // down
			'hX6B: btn_left        <= pressed; // left
			'hX74: btn_right       <= pressed; // right
			'h029: btn_fireA        <= pressed; // space
			'h014: btn_fireB        <= pressed; // ctrl

			'h005: btn_start_1     <= pressed; // F1
			'h006: btn_start_2     <= pressed; // F2
			'h004: btn_coin        <= pressed; // F3

			// JPAC/IPAC/MAME Style Codes
			'h016: btn_start_1     <= pressed; // 1
			'h01E: btn_start_2     <= pressed; // 2
			'h02E: btn_coin_1      <= pressed; // 5
			'h036: btn_coin_2      <= pressed; // 6
			'h02D: btn_up_2        <= pressed; // R
			'h02B: btn_down_2      <= pressed; // F
			'h023: btn_left_2      <= pressed; // D
			'h034: btn_right_2     <= pressed; // G
			'h01C: btn_fireA_2      <= pressed; // A
			'h01B: btn_fireB_2      <= pressed; // S
		endcase
	end
end

reg btn_up    = 0;
reg btn_down  = 0;
reg btn_right = 0;
reg btn_left  = 0;
reg btn_coin  = 0;
reg btn_fireA  =0;
reg btn_fireB  = 0;

reg btn_start_1=0;
reg btn_start_2=0;
reg btn_coin_1=0;
reg btn_coin_2=0;
reg btn_up_2=0;
reg btn_down_2=0;
reg btn_left_2=0;
reg btn_right_2=0;
reg btn_fireA_2=0;
reg btn_fireB_2=0;

wire no_rotate = status[2] | direct_video | landscape  ;
wire m_start    = btn_start_1 | joy1[7] | joy2[7];
wire m_start_2  = btn_start_2 | joy1[6] | joy2[6];
wire m_coin_1     = btn_coin    | joy1[8] | btn_coin_1  ;
wire m_coin_2     =  joy2[8] | btn_coin_2;

wire m_up     =   btn_up    | joy1[3];
wire m_down   =   btn_down  | joy1[2];
wire m_left   =  btn_left  | joy1[1];
wire m_right  =  btn_right | joy1[0];
wire m_fireA   = btn_fireA | joy1[4];
wire m_fireB   = btn_fireB | joy1[5];

wire m_up_2     =  btn_up_2    | joy2[3];
wire m_down_2   =  btn_down_2  | joy2[2];
wire m_left_2   =  btn_left_2  | joy2[1];
wire m_right_2  =  btn_right_2 | joy2[0];
wire m_fireA_2   = btn_fireA_2 | joy2[4];
wire m_fireB_2   = btn_fireB_2 | joy2[5];

wire hblank, vblank;
wire hs, vs;
wire [3:0] r,g,b;

/*
//wire CLK_VIDEO = clkref;
wire CLK_VIDEO = clk_vid;
//wire CE_PIXEL  = 1;
wire CE_PIXEL  = clkref;
assign HDMI_CLK = CLK_VIDEO;
assign VGA_CLK = CLK_VIDEO;
assign HDMI_CE = CE_PIXEL;
assign VGA_CE = CE_PIXEL;
assign HDMI_R = VGA_R;
assign HDMI_G = VGA_G;
assign HDMI_B = VGA_B;
assign HDMI_HS=VGA_HS;
assign HDMI_VS=VGA_VS;
assign HDMI_DE = VGA_DE;
assign VGA_R = {r , r};
assign VGA_G = {g , g};
assign VGA_B = {b , b};
assign VGA_HS= hs;
assign VGA_VS =vs;
assign VGA_DE = ~(vblank | hblank);
//assign VGA_F1,
*/


reg ce_pix;
always @(posedge clk_vid) begin
        reg [2:0] div;

        div <= div + 1'd1;
        ce_pix <= div == 0;
end



arcade_video #(256,400,12) arcade_video
(
	.*,

	.clk_video(clk_vid),

	.RGB_in({r,g,b}),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),

	.rotate_ccw(ccw),
	.fx(status[5:3])
);



assign AUDIO_L = {audio, 4'd0};
assign AUDIO_R = AUDIO_L;
assign AUDIO_S = 1'b0;


wire [16:0] rom_addr;
wire [15:0] rom_do;

wire [17:0] snd_addr;
wire [15:0] snd_rom_addr;
wire [15:0] snd_do;
wire        snd_vma;

wire [14:0] chr1_addr;
wire [31:0] chr1_do;
wire [15:0] sp_addr;
wire [31:0] sp_do;
wire [14:0] chr2_addr;
wire [31:0] chr2_do;

/* ROM structure
00000-1FFFF CPU1 128k
20000-2FFFF CPU2  64k
30000-4FFFF GFX1 128k
50000-8FFFF GFX2 256k

90000-9FFFF GFX3  64k
A0000-A02FF spr_color_proms 3*256b
A0300-A05FF chr_color_proms 3*256b
A0600-A08FF fg_color_proms  3*256b
A0900-A091F spr_height_prom 32b
*/


wire [24:0] sp_ioctl_addr = ioctl_addr - 20'h30000;
wire clkref;

reg port1_req, port2_req;

sdram sdram(
	.*,
	.init_n        ( pll_locked   ),
	.clk           ( clk_mem       ),
	.clkref(clkref),
	// port1 used for main + sound CPU
	.port1_req     ( port1_req    ),
	.port1_ack     ( ),
	.port1_a       ( ioctl_addr[23:1] ),
	.port1_ds      ( {ioctl_addr[0], ~ioctl_addr[0]} ),
	.port1_we      ( ioctl_download ),
	.port1_d       ( {ioctl_dout, ioctl_dout} ),
	.port1_q       ( ),

	.cpu1_addr     ( ioctl_download ? 17'h1ffff : {1'b0, rom_addr[16:1]} ),
	.cpu1_q        ( rom_do ),
	.cpu2_addr     ( ioctl_download ? 17'h1ffff : snd_addr[17:1] ),
	.cpu2_q        ( snd_do ),


	// port2 for sprite graphics
	.port2_req     ( port2_req ),
	.port2_ack     ( ),
	.port2_a       ( sp_ioctl_addr[23:1] ),
	.port2_ds      ( {sp_ioctl_addr[0], ~sp_ioctl_addr[0]} ),
	.port2_we      ( ioctl_download ),
	.port2_d       ( {ioctl_dout, ioctl_dout} ),
	.port2_q       ( ),

	.chr1_addr     ( chr1_addr ),
	.chr1_q        ( chr1_do   ),
	.chr2_addr     ( 17'h18000 + chr2_addr ),
	.chr2_q        ( chr2_do   ),
	.sp_addr       ( 16'h8000 + sp_addr ),
	.sp_q          ( sp_do     )
);

// ROM download controller
always @(posedge clk_sys) begin
	reg        ioctl_wr_last = 0;
	reg        snd_vma_r, snd_vma_r2;

	ioctl_wr_last <= ioctl_wr;
	if (ioctl_download) begin
		if (~ioctl_wr_last && ioctl_wr) begin
			port1_req <= ~port1_req;
			if (ioctl_addr >= 20'h30000) port2_req <= ~port2_req;
		end
	end

	// async clock domain crossing here (clk_snd -> clk_sys)
	snd_vma_r <= snd_vma; snd_vma_r2 <= snd_vma_r;
	if (snd_vma_r2) snd_addr <= snd_rom_addr + 18'h20000;
end

// reset signal generation
reg reset = 1;
reg rom_loaded = 0;
always @(posedge clk_sys) begin
	reg ioctl_downloadD;
	reg [15:0] reset_count;
	ioctl_downloadD <= ioctl_download;

	if (status[0] | buttons[1] | ~rom_loaded) reset_count <= 16'hffff;
	else if (reset_count != 0) reset_count <= reset_count - 1'd1;

	if (ioctl_downloadD & ~ioctl_download) rom_loaded <= 1;
	reset <= reset_count != 16'h0000;

end

wire [11:0] audio;

target_top target_top(
	.clock_sys(clk_sys),//24 MHz
	.vid_clk_en(clkref), // output clk??
	.clk_aud(clk_aud),//0.895MHz
	.reset_in(reset),
	.hwsel(core_mod), // see pkgvariant defines
	.palmode(1'b0/*palmode*/),
	.audio_out(audio),
	.switches_i(sw[0]),
	.switches_2(sw[1]),
	.usr_coin1(m_coin_1),
	.usr_coin2(m_coin_2),
	.usr_service(1'b0/*service*/),
	.usr_start1(m_start),
	.usr_start2(m_start_2),
	.p1_up(m_up),
	.p1_dw(m_down),
	.p1_lt(m_left),
	.p1_rt(m_right),
	.p1_f1(m_fireA),
	.p1_f2(m_fireB),
	.p2_up(m_up_2),
	.p2_dw(m_down_2),
	.p2_lt(m_left_2),
	.p2_rt(m_right_2),
	.p2_f1(m_fireA_2),
	.p2_f2(m_fireB_2),
	.hblank(hblank),
	.vblank(vblank),
	.VGA_VS(vs),
	.VGA_HS(hs),
	.VGA_R(r),
	.VGA_G(g),
	.VGA_B(b),

	.dl_addr(ioctl_addr - 20'hA0000),
	.dl_data(ioctl_dout),
	.dl_wr(ioctl_wr),

	.cpu_rom_addr(rom_addr),
	.cpu_rom_do( rom_addr[0] ? rom_do[15:8] : rom_do[7:0] ),
	.snd_rom_addr(snd_rom_addr),
	.snd_rom_do(snd_rom_addr[0] ? snd_do[15:8] : snd_do[7:0]),
	.snd_vma(snd_vma),
	.gfx1_addr(chr1_addr),
	.gfx1_do(chr1_do),
	.gfx3_addr(chr2_addr),
	.gfx3_do(chr2_do),
	.gfx2_addr(sp_addr),
	.gfx2_do(sp_do)
  );

endmodule

