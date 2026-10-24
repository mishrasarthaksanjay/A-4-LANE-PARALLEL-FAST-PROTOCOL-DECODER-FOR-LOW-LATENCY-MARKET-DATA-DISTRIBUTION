module vli_receiver(
    input clk,rst,in_valid,is_ascii,
    input [7:0] in_byte,
    output reg [63:0] out_value,
    output reg out_valid
);
    reg [63:0] acc;
    always @(posedge clk) begin
        if(rst) begin
            acc<=64'd0;
            out_value<=64'd0;
            out_valid<=1'b0;
        end
        else begin
            out_valid<=1'b0;
            if(in_valid) begin
                if(is_ascii) begin
                    // FAST ASCII: 7-bit characters, stop bit on the last byte.
                    // Packed into the low bytes of out_value, first character first.
                    if(in_byte[7]) begin
                        out_value<=(acc<<8)|{1'b0,in_byte[6:0]};
                        acc<=64'd0;
                        out_valid<=1'b1;
                    end
                    else
                        acc<=(acc<<8)|{1'b0,in_byte[6:0]};
                end
                else if(in_byte[7]) begin
                    out_value<=(acc<<7)|in_byte[6:0];
                    acc<=64'd0;
                    out_valid<=1'b1;
                end
                else
                    acc<=(acc<<7)|in_byte[6:0];
            end
        end
    end
endmodule