module fast_fieldop(
    input clk,rst,
    input [2:0] field_index,operator,
    input [63:0] r_value,constant_value,
    input present,fieldopst,
    output reg [63:0] out_value
);
    reg [63:0] memr[0:4];
    reg [63:0] res;
    integer i;
    always @(*) begin
        case(operator)
            3'd0: res=r_value;
            3'd1: res=present?r_value:memr[field_index];
            3'd2: res=constant_value;
            3'd3: res=present?r_value:memr[field_index]+64'd1;
            3'd4: res=memr[field_index]+r_value;
            default: res=64'd0;
        endcase
    end
    always @(posedge clk) begin
        if(rst) begin
            out_value<=64'd0;
            for(i=0;i<5;i=i+1)
                memr[i]<=64'd0;
        end
        else if(fieldopst) begin
            out_value<=res;
            memr[field_index]<=res;
        end
    end
endmodule