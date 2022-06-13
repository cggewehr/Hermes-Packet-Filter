
module PacketFilterTB#(
	parameter XMax = 8'd2,
	parameter YMax = 8'd2,
	parameter TimeoutValue = 10,
	parameter AmountOfTestCases = 500
)
();

logic clk, reset;
logic rx[0:(XMax*YMax)-1], tx[0:(XMax*YMax)-1];
logic[31:0] data_in[0:(XMax*YMax)-1], data_out[0:(XMax*YMax)-1];
logic credit_i[0:(XMax*YMax)-1], credit_o[0:(XMax*YMax)-1];
logic clock_rx[0:(XMax*YMax)-1], clock_tx[0:(XMax*YMax)-1], clock[0:(XMax*YMax)-1];

typedef enum {NoError, TimeoutOnSize, TimeoutOnPayload, BadAddressChecksum, BadSizeChecksum, ExtraPayloadFlit} packetError_t;

class HermesPacket;

	logic [7:0] XMax;
	logic [7:0] YMax;
	int TimeoutValue;

	rand logic[31:0] addr;
	rand logic[31:0] size;
	rand logic[31:0] payload[];
	
	rand int sizeDelay;
	rand int payloadDelays[];
	rand int timeoutFlitIndex;
	
	rand int newPacketDelay;
	
	//typedef enum {NoError, TimeoutOnSize, TimeoutOnPayload, BadAddressChecksum, BadSizeChecksum} packetError_t;
	rand packetError_t packetError;

    constraint packetAddress {this.addr[15:8] inside {[1:XMax-1]}; this.addr[7:0] inside {[1:YMax-1]};}

	constraint packetSize {this.size inside {[3:10]};}

	constraint payloadSize {solve size before payload; 
	
			(this.packetError != ExtraPayloadFlit) -> this.payload.size() == this.size;
			(this.packetError == ExtraPayloadFlit) -> this.payload.size() == this.size + 10;
			
	}
	
	constraint payloadDelaysSize {solve size before payloadDelays; this.payloadDelays.size() == this.size;}
	
	constraint sizeDelayValue {
	
		solve packetError before sizeDelay;
		
		(this.packetError == TimeoutOnSize) -> this.sizeDelay inside {[TimeoutValue:TimeoutValue*2]};
		(this.packetError != TimeoutOnSize) -> this.sizeDelay inside {[0:TimeoutValue-2]};
		
	}
	
	constraint payloadDelaysValues {
	
		solve packetError before payloadDelays;
        solve packetError before timeoutFlitIndex;
		solve timeoutFlitIndex before payloadDelays;
		
		(this.packetError == TimeoutOnPayload) -> this.timeoutFlitIndex inside {[0:this.size - 1]};
		(this.packetError != TimeoutOnPayload) -> this.timeoutFlitIndex == -1;
		
		foreach(payloadDelays[i])
			(i != this.timeoutFlitIndex) -> this.payloadDelays[i] inside {[0:TimeoutValue-2]};

		(this.packetError == TimeoutOnPayload) -> this.payloadDelays[timeoutFlitIndex] inside {[TimeoutValue:TimeoutValue*2]};

    }
	
	constraint newPacketDelayValue {newPacketDelay inside {[0:TimeoutValue*2]};}

	function new(logic[7:0] XMax, logic[7:0] YMax, int TimeoutValue);

		this.XMax = XMax;
		this.YMax = YMax;
		this.TimeoutValue = TimeoutValue;

	endfunction
	
	function post_randomize();

		bit[15:0] checksumIV;
		checksumIV = {this.XMax, this.YMax};
	
		// Set checksums on ADDR and SIZE
		// this.addr[31:16] = this.addr[15:0] ^ {XMax, YMax};
		for (int i = 0; i < 8; i++)
			this.addr[i+16] = this.addr[2*i] ^ this.addr[2*i + 1] ^ checksumIV[2*i] ^ checksumIV[2*i + 1];
		
		// this.size[31:16] = this.addr[31:16] ^ this.size[15:0];
		for (int i = 0; i < 8; i++)
			this.size[i+24] = this.size[3*i] ^ this.size[3*i + 1] ^ this.size[3*i + 2] ^ this.addr[i+16];
		
		// Set intentionally bad checksums
		if (this.packetError == BadAddressChecksum)
			// this.addr[31:16] = !this.addr[31:16];
			this.addr[23:16] = !this.addr[23:16];
			
		if (this.packetError == BadSizeChecksum)
			// this.size[31:16] = !this.size[31:16];
			this.size[31:24] = !this.size[31:24];
		
	endfunction

endclass

task drivePacket(HermesPacket packet, int port);

	@(negedge clk);

	data_in[port] <= packet.addr;
	rx[port] <= 1'b1;
	wait (credit_o[port]);

	@(negedge clk);
	rx[port] <= 1'b0;

	repeat(packet.sizeDelay)
		@(negedge clk);

	data_in[port] = packet.size;
	rx[port] <= 1'b1;
	wait (credit_o[port]);

	@(negedge clk);
	rx[port] <= 1'b0;

	foreach (packet.payload[i]) begin
		
		repeat (packet.payloadDelays[i])
			@(negedge clk);

		data_in[port] <= packet.payload[i];
		rx[port] <= 1'b1;
		wait (credit_o[port]);

		@(negedge clk);
		rx[port] <= 1'b0;

	end

	repeat (packet.newPacketDelay)
		@(negedge clk);
	
	// Reset if packet was generated with errors
	//if (packet.packetError != NoError) begin

	//	reset <= 1'b1;
	//	@(negedge clk);
	//	reset <= 1'b0;

	//end

endtask

HermesPacket packet;

task run();

	reset <= 1'b1;
	@(negedge clk);
	@(negedge clk);
	@(negedge clk);
	reset <= 1'b0;

	for (int i = 0; i < AmountOfTestCases; i++) begin

		packet = new(XMax, YMax, TimeoutValue);
		//packet.randomize() with {packetError == TimeoutOnPayload;};
		packet.randomize() with {addr == 16'h0101;};
		drivePacket(packet, 3);

		// TODO: Sample covergroup

	end

    $finish;

endtask

// TODO: covergroup with coverage on "packetError" and cross on "packetError" transition

initial begin
	run();
end

initial begin

	clk = 1'b0;

	forever 
		#10ns clk = !clk;

end 

for (genvar i = 0; i < (XMax*YMax); i++) begin
    assign clock_rx[i] = clk;
    assign clock[i] = clk;
    assign credit_i[i] = 1'b1;
end

// DUT Hermes, parameterized dimensions (default is 2x2)
NoC #(
    .X_ROUTERS(XMax),
    .Y_ROUTERS(YMax),
    .TimeoutMax(TimeoutValue)
) DUT (

    .reset(reset),
    .clock(clock),

    .clock_rxLocal(clock_rx),
    .rxLocal(rx),
    .data_inLocal(data_in),
    .credit_oLocal(credit_o),

    .clock_txLocal(clock_tx),
    .txLocal(tx),
    .data_outLocal(data_out),
    .credit_iLocal(credit_i)
);

endmodule
