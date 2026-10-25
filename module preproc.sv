module fast_preproc(
    input [63:0] recv_value,
    input [6:0] field_width,
    input field_signed,field_ascii,
    output reg [63:0] proc_value
);
    reg [63:0] mask;
    always @(*) begin
        if(field_ascii)
            proc_value=recv_value;
        else begin
            if(field_width==64)
                mask=64'hFFFFFFFFFFFFFFFF;
            else
                mask=(64'd1<<field_width)-1;
            if(field_signed)
                proc_value=$signed(recv_value<<(64-field_width))>>>(64-field_width);
            else
                proc_value=recv_value&mask;
        end
    end
endmodule