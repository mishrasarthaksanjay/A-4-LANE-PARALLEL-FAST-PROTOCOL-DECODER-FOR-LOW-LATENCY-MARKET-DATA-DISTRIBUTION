module fast_sequencer #(parameter STEP=3'd1)(
    input clk,rst,start,done,
    input [2:0] start_index,last_index,
    output [2:0] field_index
);
    reg [2:0] index;
    wire [3:0] next_index;
    assign field_index=index;
    assign next_index={1'b0,index}+{1'b0,STEP};
    always @(posedge clk) begin
        if(rst)
            index<=3'd0;
        else if(start)
            index<=start_index;
        else if(done) begin
            if(index<last_index && next_index<={1'b0,last_index})
                index<=next_index[2:0];
        end
    end
endmodule
