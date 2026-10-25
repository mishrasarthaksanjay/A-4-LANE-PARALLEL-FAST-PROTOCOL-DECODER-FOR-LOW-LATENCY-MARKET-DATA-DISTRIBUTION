module fast_pmap(
    input clk,rst,
    input [7:0] in_byte,
    input load,pop,
    output stop
);
    reg [6:0] flags;
    assign stop=flags[6];
    always @(posedge clk) begin
        if(rst)
            flags<=7'd0;
        else if(load)
            flags<=in_byte[6:0];
        else if(pop)
            flags<={flags[5:0],1'b0};
    end
endmodule