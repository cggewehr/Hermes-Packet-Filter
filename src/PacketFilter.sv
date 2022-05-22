
module PacketFilter #(
    parameter logic[7:0] XMax = 8'd3,
    parameter logic[7:0] YMax = 8'd3,
    parameter int TimeoutMax = 10
)
(

    input logic clk,
    input logic reset,
    
    input logic rx,
    input logic[31:0] data_in,
    output logic credit_o,
    
    output logic tx,
    output logic[31:0] data_out,
    input logic credit_i

);

// 2 FIFO registers (A & B)
logic[31:0] A;
logic[31:0] B;
logic AIsValid;
logic BIsValid;
logic AIsHeader;
logic BIsHeader;

// Timeout counter (counts how many consecutive cycles an attempt to write a flit into A was not performed)
logic timeoutEnable;
logic timeoutFlag;
logic[$clog2(TimeoutMax)-1:0] timeoutCounter;

// Flit counter (counts how many payload flits are yet to be transmitted in a packet whose header has been validate via checksums)
logic[15:0] size;

logic paddingEnable;

logic[15:0] addressChecksum;
logic[15:0] sizeChecksum;
logic validAddressChecksum;
logic validSizeChecksum;

typedef enum logic [1:0] {Saddr, Ssize, Spayload, Spad} state_t;
state_t state;

logic invalidateBuffer;
logic txEnable;

assign tx = (BIsValid && (txEnable || validSizeChecksum) || paddingEnable) ? 1'b1 : 1'b0;
assign data_out = paddingEnable ? 32'd0 : B;
assign credit_o = (!AIsValid || (AIsValid && !BIsValid && !paddingEnable) || (AIsValid && BIsValid && credit_i)) ? 1'b1 : 1'b0;

// Write to A & B FIFO registers. A conditionally <= data_in, data_out <= B.
always_ff @(posedge clk) begin

	if (reset) begin
		AIsValid <= 1'b0;
		BIsValid <= 1'b0;
		AIsHeader <= 1'b0;
		BIsHeader <= 1'b0;
	end
	
	// Can write to A if: A is empty OR B is empty (B <= A) OR B is being consumed (credit_i == 1)
	if (!timeoutFlag && !paddingEnable && ((rx && !AIsValid) || (rx && AIsValid && !BIsValid) || (rx && AIsValid && BIsValid && credit_i))) begin
	
		A <= data_in;
		AIsValid <= 1'b1;

		// Determine if the flit being written into A is a header flit (either ADDR or SIZE)
		if ((size == 2 && AIsValid && BIsValid && credit_i) || (size == 1 && !AIsValid && BIsValid && BIsHeader && credit_i) || (size == 0 && !(AIsHeader && BIsHeader)))
			AIsHeader <= 1'b1;
		else
			AIsHeader <= 1'b0;
		
	end
	
	// A is not valid if no new value has been written this cycle and B is empty (meaning this cycle, the current value of A will be written into B and no new value was provided)
    // Also invalidate A if timeout or invalid SIZE checksum
	if ((!rx && !BIsValid) || (!rx && AIsValid && BIsValid && credit_i && (txEnable || validSizeChecksum)) || timeoutFlag || (AIsValid && BIsValid && !validSizeChecksum && BIsHeader)) begin
		AIsValid <= 1'b0;
        AIsHeader <= 1'b0;
    end

	// Can write to B if: A is valid and (B is not valid or B is valid, but was consumed in the current cycle)
    // Waits for padding to be done before writting to B, since checksum computations are performed on A value, and the result of these computations must be observed by the FSM within the Saddr and Ssize states
	if (!paddingEnable && !timeoutFlag && (AIsValid && !BIsValid) || (AIsValid && BIsValid && credit_i)) begin
		B <= A;
		BIsValid <= 1'b1;
		BIsHeader <= AIsHeader;
	end
	
	// B is not valid if no new value has been written this cycle and not waiting OR timeout on ADDR flit
	if ((!AIsValid && credit_i && txEnable) || timeoutFlag || invalidateBuffer) begin
		BIsValid <= 1'b0;
		BIsHeader <= 1'b0;
    end
	
end

// Combinationally determine valid checksums from flit written into A FIFO register
assign addressChecksum = A[15:0] ^ {XMax, YMax};
assign sizeChecksum = A[15:0] ^ B[31:16];
assign validAddressChecksum = ((A[31:16] == addressChecksum) && AIsValid) ? 1'b1 : 1'b0;
assign validSizeChecksum = ((A[31:16] == sizeChecksum) && AIsHeader && AIsValid && BIsValid && (state == Ssize)) ? 1'b1 : 1'b0;

// Timeout Counter
always_ff @(posedge clk) begin

    if (reset)
        timeoutCounter <= TimeoutMax - 1;

    else begin

		timeoutFlag <= 1'b0;
    
        if (timeoutEnable) begin
		
			if (rx == 1'b1) begin
				timeoutCounter <= TimeoutMax - 1;
	
			end else begin
        
                if (!timeoutFlag)
				    timeoutCounter <= timeoutCounter - 1;
		
				if (timeoutCounter == 1) begin
					timeoutCounter <= TimeoutMax - 1;
					timeoutFlag <= 1'b1;
				end 
					
			end
			
        end
    
    end

end

// Control FSM, synchronous reset
always_ff @(posedge clk) begin

    if (reset) begin 
	
        invalidateBuffer <= 1'b0;
        txEnable <= 1'b0;
		
        timeoutEnable <= 1'b0;
        paddingEnable <= 1'b0;

        size <= 16'd0;
		
        state <= Saddr;
		
    end else begin 
        
		// Wait for a new valid ADDR flit
        if (state == Saddr) begin 
		
			invalidateBuffer <= 1'b0;
	
            // Remains waiting for an ADDR flit until a valid ADDR flit checksum is seen. Non-valid ADDR flits are discarted and not propagated to Router local port.
            if (validAddressChecksum) begin
                timeoutEnable <= 1'b1;
                state <= Ssize;
            end
            
		// Wait for a new SIZE flit and monitor for timeout
        end else if (state == Ssize) begin
			
			// Timed-out waiting for a SIZE flit. 
			if (timeoutFlag) begin

				timeoutEnable <= 1'b0;
				state <= Saddr;
				
			end else begin
        
                // Valid SIZE flit, wait for first payload flit
				if (AIsValid && validSizeChecksum) begin

					txEnable <= 1'b1;
					size <= A[15:0];
					state <= Spayload;

                // SIZE checksum fail, invalidade ADDR flit on B and SIZE flit on A and wait for new valid ADDR flit
				end else if (AIsValid && !validSizeChecksum) begin

					invalidateBuffer <= 1'b1;
					state <= Saddr;

				end
					
			end
		
		// Transmit packet payload and monitor for timeout
		end else if (state == Spayload) begin
		
			// Timed-out waiting for a flit
			if (timeoutFlag) begin
			
				timeoutEnable <= 1'b0;
				paddingEnable <= 1'b1;
				state <= Spad;
				
            // Payload flit in B register was consumed by Router local port
			end else if (BIsValid && !BIsHeader && credit_i) begin
			
				size <= size - 1;
				
                // Last payload flit sent, wait for ADDR flit to be written to A
				if (size == 1) begin

                    txEnable <= 1'b0;
				
					// Skip to waiting for SIZE flit if there already is a valid ADDR flit in A
					if (AIsValid && validAddressChecksum)
						state <= Ssize;

				    else begin

                        if (!validAddressChecksum)
                            invalidateBuffer <= 1'b1;

					    state <= Saddr;

		            end
			
				end	
			
			end
	
		// Pad remainder of a packet's payload with null flits after timeout
		end else if (state == Spad) begin
		    
            if (credit_i) begin

			    size <= size - 1;
			    
                // Last padding flit sent, wait for ADDR flit to be written to B
			    if (size == 1) begin
			    
                    txEnable <= 1'b0;
				    paddingEnable <= 1'b0;
		    
					// Skip to waiting for SIZE flit if there already is a valid ADDR flit in A
				    if (AIsValid && validAddressChecksum)
					    state <= Ssize;

				    else begin

                        if (!validAddressChecksum)
                            invalidateBuffer <= 1'b1;

					    state <= Saddr;

		            end

			    end	

		    end

        end 
    
    end
	
end

endmodule
