module hiscore #(parameter ADDRESSWIDTH=10) (
	input				clk,
	input				reset,
	input				mode,				// 0 = manual, 1 = off
	input	[24:0]	delay,
	input				ioctl_upload,
	input				ioctl_download,
	input				ioctl_wr,
	input	[24:0]	ioctl_addr,
	input	[7:0]		ioctl_dout,
	input	[7:0]		ioctl_din,
	input	[7:0]		ioctl_index,
	
	output	[ADDRESSWIDTH-1:0]	ram_address,
	output	[7:0]						data_to_ram,
	output	reg						ram_write,
	output	reg						pause
);

/*
00 00 00 0b 0f 10 01 00
00 00 00 23 0f 04 12 00
[ addr (4)]len start end pad
addr -> address of ram (in memory map)
len -> how many bytes
start -> wait for this value at start
end -> wait for this value at end
*/


//reg [25:0] timer_default = 21'h1FFFFF;
//reg [25:0] timer_default = 25'h1FFFFFF; // 2.8 seconds
//reg [25:0] timer_default = 24'hFFFFFF; // 1.4 seconds
//reg [25:0] timer_default = 24'h7FFFFF; // 0.7 seconds
//reg [25:0] timer_default = 24'h3FFFFF; // 0.35 seconds
//reg [25:0] timer_default = 24'h1FFFFF; // 0.175 seconds
reg [25:0] timer_default = 24'h7FFFF; // 0.04 seconds

assign ram_address = ram_addr[ADDRESSWIDTH-1:0];

//reg  [7:0] ioctl_dout_r;
reg	[7:0]		ioctl_dout_r2;
reg	[7:0]		ioctl_dout_r3;
reg	[2:0]		state = 3'b0;
reg				reset_last = 1'b0;
reg	[25:0]	timer;
reg	[3:0]		counter = 4'b0;

reg	[7:0]		last_index;
reg				last_ioctl_download=0;
reg	[24:0]	ram_addr;
reg	[3:0]		total_entries=4'b0;
reg	[24:0]	old_io_addr;
reg	[24:0]	base_io_addr;
reg	[24:0]	end_addr;
reg	[24:0]	local_addr;
wire	[23:0]	addr_base;
wire	[7:0]		length;
wire	[7:0]		start_val;
wire	[7:0]		end_val;

reg				downloading_config;
reg				downloading_dump;
reg				downloaded_config;
reg				downloaded_dump;
reg	[3:0]		initialised;

assign downloading_config = ioctl_download && ioctl_wr && (ioctl_index==3);
assign downloading_dump = ioctl_download && ioctl_wr && (ioctl_index==4);

// RAM chunks used to store configuration data
// - address_table
// - length_table
// - startdata_table
// - enddata_table
dpram #(
        .widthad_a(4),
        .width_a(24),
        .widthad_b(4),
        .width_b(24)
)
address_table(
	.address_a(ioctl_addr[6:3]),
	.clock_a(clk),
	.data_a({ioctl_dout_r2,  ioctl_dout_r3, ioctl_dout}), // ignore first byte
	.wren_a(downloading_config & ~ioctl_addr[2] &  ioctl_addr[1] & ioctl_addr[0]),
	.clock_b(clk),
	.q_b(addr_base),
	.address_b(counter)
);

dpram #(
        .widthad_a(4),
        .width_a(8),
        .widthad_b(4),
        .width_b(8)
		  )
length_table(
	.address_a(ioctl_addr[6:3]),
	.clock_a(clk),
	.data_a(ioctl_dout),
	.wren_a(downloading_config & ioctl_addr[2] & ~ioctl_addr[1] & ~ioctl_addr[0]), // ADDR b100
	.clock_b(clk),
	.q_b(length),
	.address_b(counter)
);
dpram #(
        .widthad_a(4),
        .width_a(8),
        .widthad_b(4),
        .width_b(8)
		  )
startdata_table(
	.address_a(ioctl_addr[6:3]),
   .clock_a(clk),
	.data_a(ioctl_dout),
	.wren_a(downloading_config & ioctl_addr[2] & ~ioctl_addr[1] & ioctl_addr[0]), // ADDR b101
	.clock_b(clk),
	.q_b(start_val),
	.address_b(counter)
);
dpram #(
        .widthad_a(4),
        .width_a(8),
        .widthad_b(4),
        .width_b(8)
		  )
enddata_table(
	.address_a(ioctl_addr[6:3]),
	.clock_a(clk),
	.data_a(ioctl_dout),
	.wren_a(downloading_config & ioctl_addr[2] & ioctl_addr[1] & ~ioctl_addr[0]), // ADDR b110
	.clock_b(clk),
	.q_b(end_val),
	.address_b(counter)
);

// RAM chunk used to store hiscore data
dpram #(
        .widthad_a(8),
        .width_a(8),
        .widthad_b(8),
        .width_b(8)
		  )
hiscoredata (
	.clock_a(clk),
	.wren_a(downloading_dump),
	.address_a(ioctl_addr[7:0]),
	.data_a(ioctl_dout),
	.clock_b(clk),
	.address_b(local_addr[7:0]),
	.wren_b(ioctl_upload), 
	.data_b(ioctl_din),
	.q_b(data_to_ram)
);


always @(posedge clk)
begin
	if (downloading_config)
	begin
		// Save configuration data into tables
		//if(ioctl_wr & ~ioctl_addr[2] & ~ioctl_addr[1] & ~ioctl_addr[0]) ioctl_dout_r <= ioctl_dout;
		if(ioctl_wr & ~ioctl_addr[2] & ~ioctl_addr[1] &  ioctl_addr[0]) ioctl_dout_r2 <= ioctl_dout;
		if(ioctl_wr & ~ioctl_addr[2] & ioctl_addr[1] & ~ioctl_addr[0]) ioctl_dout_r3 <= ioctl_dout;
		// Keep track of the largest entry during config download
		total_entries <= ioctl_addr[6:3];
	end
//	if (ioctl_wr & ioctl_download)
//		$display("HISCORE ioctl_addr %x %b ioctl_dout %x ioctl_dout_r %x", ioctl_addr,ioctl_addr[2:0],ioctl_dout,ioctl_dout_r);
//	if (ioctl_download & ioctl_wr & ~ioctl_addr[2] &  ioctl_addr[1] & ioctl_addr[0])
//		$display("HI HISCORE ioctl_addr %x %b ioctl_dout_r2 %x ioctl_dout_r3 %x ioctl_dout ", ioctl_addr,ioctl_addr[2:0],ioctl_dout_r2,ioctl_dout_r3,ioctl_dout);
//	if (ioctl_download & ioctl_wr & ioctl_addr[2] &  ioctl_addr[1] & ~ioctl_addr[0] &(ioctl_index==3))
//		$display("ENDVAL ioctl_addr %x %b counter %x ioctl_dout %x ", ioctl_addr,ioctl_addr[2:0],ioctl_addr[6:3],ioctl_dout);

	// Track completion of configuration and dump download
	if ((last_ioctl_download != ioctl_download) && (ioctl_download == 1'b0))
	begin
		if (last_index==3) downloaded_config <= 1'b1;
		if (last_index==4) downloaded_dump <= 1'b1;
	end

	// Track last ioctl values 
	last_ioctl_download <= ioctl_download;
	last_index <= ioctl_index;

	// Generate last address of entry to check end value
	end_addr <= addr_base + length - 1'b1;

	// Check for state machine initalise/reset
	if (initialised == 1'b0 || (reset_last == 1'b1 && reset == 1'b0))
	begin
		timer = (delay > 0) ? delay : timer_default;
		state <= 3'b000;
		counter <= 4'b0;
		initialised <= initialised + 1'b1;
	end
	reset_last <= reset;

	// active pause signal when necessary
	pause <= ioctl_upload || (ioctl_download && ioctl_index == 4);
	
	// Upload scores to HPS
	if (ioctl_upload == 1'b1 && mode == 1'b0) 
	begin
	
		// generate addresses to read high score from game memory. Base addresses off ioctl_address
		if (ioctl_addr == 25'b0) begin
			local_addr <= 25'b0;
			base_io_addr <= 25'b0;
			counter <= 4'b0;
		end
		// Move to next entry when last address is reached
		if (old_io_addr!=ioctl_addr && ram_addr==end_addr[24:0])
		begin
			counter <= counter + 1'b1;
			base_io_addr <= ioctl_addr;
		end
		// Set game ram address for reading back to HPS
		ram_addr <= addr_base + (ioctl_addr - base_io_addr);
		// Set local addresses to update cached dump in case of reset
		local_addr <= ioctl_addr;
		// Mark dump as readable
		downloaded_dump <= 1'b1;
	end
	// State machine to write data to game RAM
	else if (downloaded_dump == 1'b1 && ioctl_upload == 1'b0 && reset == 1'b0 && mode == 1'b0) begin
		// Wait for timer before starting state machine
		if (timer > 0) 
		begin
			timer = timer - 1'b1;
		end
		else
		begin
			case (state)
				// Sit in first states until game memory is validated
				// to match hiscore table start/end values
				// start with counter == 0?
				3'b000: // start
					// setup beginning addr 
					begin
	//					$display("state 0 ram_addr %x addr_base %x",ram_addr,addr_base);
						state <= 3'b001;
						local_addr <= 25'b0;
						base_io_addr <= 25'b0;
						ram_addr <= {1'b0, addr_base};
					end

				3'b001:  //  check each start_val
					begin
						ram_addr <= {1'b0, addr_base};
	//					$display("HI HISCORE ?start_val==ioctl_din ioctl_din %x start_val %x ram_addr %x addr_base %x counter %x",ioctl_din,start_val,ram_addr,addr_base,counter);
						// Check for matching start value
						if (ioctl_din == start_val)
						begin
	//						$display("HI HISCORE start_val==ioctl_din");
							// Prepare address for end check and move to next state
							state <= 3'b010;
							ram_addr <= end_addr;
						end
					end

				3'b010:  // check each end_val
					begin
						ram_addr <= end_addr;
						// $display("HI HISCORE ?end_val==ioctl_din ioctl_din %x end_val %x ram_addr %x counter %x",ioctl_din,end_val,ram_addr,counter);
						if (ioctl_din == end_val)
						begin
							//$display("HI HISCORE end_val==ioctl_din");

							if (counter==total_entries)
							begin
								// If this was the last entry then move to phase II, copying scores into game ram
								state <= 3'b110;
//								$display("state 010 addr_base %x %x %x ",addr_base,local_addr,counter);
								counter <= 0;
								ram_write <= 0;
								ram_addr <= {1'b0, addr_base};
							end
							else begin  
								// Increment counter and check next entry
	//							$display("try next entry");
								counter <= counter + 1'b1;
								state <= 3'b000;
							end
						end
					end

				//
				//  this section walks through our temporary ram and copies into game ram
				//  it needs to happen in chunks, because the game ram isn't necessarily consecutive
				3'b011:
					begin
						local_addr <= local_addr + 1'b1;
	//					$display("DUMP local_addr %x ram_addr %x addr_base %x base_io_addr %x end_addr %x ram_write %x",local_addr,ram_addr,addr_base,base_io_addr,end_addr,ram_write);
						if (ram_addr == end_addr[24:0])
						begin
							if (counter == total_entries) 
							begin 
								// 
	//							$display("counter==total %x == %x done writing",counter,total_entries);
								state <= 3'b101;
							end
							else
							begin
	//							$display("increment counter %x ",counter);
								counter <= counter + 1'b1;
								base_io_addr <= local_addr + 1'b1;
								state <= 3'b110;
							end
						end 
						else 
						begin
							state<=3'b111;
						end
						ram_write<=0;
					end

				3'b100:
					begin // our local ram should be correct, 
						state <= 3'b011;
	//					$display("state 100  addr_base %x %x %x %x",addr_base,local_addr,counter,ram_addr);
						ram_addr <= {1'b0, addr_base};
						ram_write <= 1;
					end

				3'b101:
					begin
						ram_write <= 0;
					end

				3'b110:  // counter is correct, next state the output of our local ram will be correct
					begin
	//					$display("state 110 addr_base %x %x %x  ram_addr ",addr_base,local_addr,counter,ram_addr);
						state <= 3'b100;
					end

				3'b111: // local ram is  correct
					begin
						ram_addr <= addr_base + (local_addr - base_io_addr);
						ram_write <= 1;
						state <= 3'b011;
					end

			endcase

//			if (ram_write)
//				$display("RAMWRITE: local_addr %x ram_addr %x ram_write %x data_to_ram %x",local_addr,ram_addr,ram_write,data_to_ram);
			
		end
		 
	end
	 
	old_io_addr<=ioctl_addr;
end




endmodule