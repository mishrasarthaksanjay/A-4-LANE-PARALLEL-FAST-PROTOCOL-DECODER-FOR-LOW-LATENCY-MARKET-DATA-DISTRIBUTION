`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/13/2026 01:35:55 AM
// Design Name: 
// Module Name: fast_quadlane
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

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


module smt_ram(
    input clk,en,
    input [2:0] waddr,
    input [75:0] win,
    input [2:0] raddr1,raddr2,raddr3,raddr4,
    output [75:0] rin1,rin2,rin3,rin4
);
    // Control word:
    //   [75]    1 = FAST ASCII string, 0 = integer
    //   [74:11] constant (integer value, or packed ASCII in the low bytes)
    //   [10:8]  operator: 0 none, 1 copy, 2 constant, 3 increment, 4 delta
    //   [7]     signed (integers only)
    //   [6:0]   bit width (integers) / unused for ASCII
    //
    // BSE-style 5-field slice of MarketDataIncrementalRefresh (MsgType X):
    //   0 MsgType    ASCII constant "X"
    //   1 SeqNum     uInt16 increment (PMAP)
    //   2 Symbol     ASCII copy       (PMAP)  e.g. TCS / RELIANCE
    //   3 SecurityID uInt16 copy      (PMAP)
    //   4 LastPx     int32  delta
    reg [75:0] mem[0:4];
    initial begin
        mem[0]={1'b1,64'h58,3'd2,1'b0,7'd8};
        mem[1]={1'b0,64'd0,3'd3,1'b0,7'd16};
        mem[2]={1'b1,64'd0,3'd1,1'b0,7'd8};
        mem[3]={1'b0,64'd0,3'd1,1'b0,7'd16};
        mem[4]={1'b0,64'd0,3'd4,1'b1,7'd32};
    end
    always @(posedge clk) begin
        if(en)
            mem[waddr]<=win;
    end
    assign rin1=mem[raddr1];
    assign rin2=mem[raddr2];
    assign rin3=mem[raddr3];
    assign rin4=mem[raddr4];
endmodule


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


module fast_lane_core(
    input clk,rst,start,
    input in_valid,
    input [7:0] in_byte,
    input receive_allow,output_grant,pmap_flag,pmap_turn,
    input [75:0] control_word,
    input [2:0] field_index,last_index,
    input [63:0] recv_value,
    output [2:0] state,
    output receive_done,stream_skip,output_done,uses_bit,pmap_consume,
    output [63:0] out_value,
    output out_valid
);
    localparam IDLE=3'd0,FETCH=3'd1,DECODE=3'd2,RECEIVE=3'd3,
               PREPROC=3'd4,FIELDOP=3'd5,OUTPUT=3'd6;

    reg [2:0] state_r,next;
    reg [2:0] cnt;
    reg [63:0] val;
    reg recv_pending;
    reg present_r;

    wire take,fieldopst;
    wire [6:0] field_width;
    wire field_signed,field_ascii;
    wire [2:0] operator;
    wire [63:0] constant_value;
    wire [63:0] proc_value,fieldop_out;

    assign state=state_r;
    assign field_width=control_word[6:0];
    assign field_signed=control_word[7];
    assign operator=control_word[10:8];
    assign constant_value=control_word[74:11];
    assign field_ascii=control_word[75];
    assign uses_bit=(operator==3'd1)||(operator==3'd3);
    assign take=in_valid&&(state_r==RECEIVE)&&receive_allow;
    assign receive_done=take&&in_byte[7];
    assign stream_skip=(state_r==DECODE)&&(next==PREPROC);
    assign pmap_consume=(state_r==DECODE)&&uses_bit&&pmap_turn;
    assign fieldopst=(state_r==FIELDOP)&&(cnt==3'd0);
    assign output_done=(state_r==OUTPUT)&&output_grant&&(cnt==3'd1);
    assign out_valid=(state_r==OUTPUT)&&output_grant&&(cnt==3'd0);
    assign out_value=fieldop_out;

    fast_preproc u_preproc(
        .recv_value(val),
        .field_width(field_width),
        .field_signed(field_signed),
        .field_ascii(field_ascii),
        .proc_value(proc_value)
    );

    fast_fieldop u_fieldop(
        .clk(clk),
        .rst(rst),
        .field_index(field_index),
        .operator(operator),
        .r_value(proc_value),
        .constant_value(constant_value),
        .present(present_r),
        .fieldopst(fieldopst),
        .out_value(fieldop_out)
    );

    always @(posedge clk) begin
        if(rst) begin
            state_r<=IDLE;
            cnt<=3'd0;
            val<=64'd0;
            recv_pending<=1'b0;
            present_r<=1'b1;
        end
        else begin
            state_r<=next;
            if(state_r==OUTPUT&&!output_grant)
                cnt<=cnt;
            else
                cnt<=(next!=state_r)?3'd0:cnt+3'd1;
            if(receive_done)
                recv_pending<=1'b1;
            if(state_r==PREPROC&&recv_pending) begin
                val<=recv_value;
                recv_pending<=1'b0;
            end
            // latch the presence decision at the moment DECODE resolves it,
            // so a later pop of the shared PMAP register (by this lane or
            // another) can't change what FIELDOP sees at commit time
            if(state_r==DECODE && (next==RECEIVE || next==PREPROC))
                present_r<=uses_bit?pmap_flag:1'b1;
        end
    end

    always @(*) begin
        next=state_r;
        case(state_r)
            IDLE:
                if(start)
                    next=FETCH;
            FETCH:
                next=DECODE;
            DECODE: begin
                if(operator==3'd2)
                    next=PREPROC;
                else if(uses_bit) begin
                    if(pmap_turn) begin
                        if(pmap_flag)
                            next=RECEIVE;
                        else
                            next=PREPROC;
                    end
                    // else: stay in DECODE, waiting its turn
                end
                else
                    next=RECEIVE;
            end
            RECEIVE:
                if(receive_done)
                    next=PREPROC;
            PREPROC:
                next=FIELDOP;
            FIELDOP:
                if(cnt==3'd5)
                    next=OUTPUT;
            OUTPUT: begin
                if(!output_grant)
                    next=OUTPUT;
                else if(cnt==3'd1) begin
                    if(field_index==last_index)
                        next=IDLE;
                    else
                        next=FETCH;
                end
            end
            default:
                next=IDLE;
        endcase
    end
endmodule


module fast_lane(
    input clk,rst,start,
    input in_valid,
    input [7:0] in_byte,
    output in_ready,
    output [63:0] out_value,
    output out_valid
);
    localparam IDLE=2'd0,PMAP=2'd1,RUN=2'd2;

    reg [1:0] state;
    reg [2:0] expected_field;
    reg [2:0] expected_recv_field;
    reg skip_pend0, skip_pend1, skip_pend2, skip_pend3;

    wire pmap_load,pmap_pop,pmap_flag;
    wire [2:0] field_index0,field_index1,field_index2,field_index3;
    wire [75:0] control_word0,control_word1,control_word2,control_word3;
    wire field_ascii0,field_ascii1,field_ascii2,field_ascii3;
    wire recv_is_ascii;
    wire [2:0] lane_state0,lane_state1,lane_state2,lane_state3;
    wire receive_allow0,receive_allow1,receive_allow2,receive_allow3;
    wire receive_done0,receive_done1,receive_done2,receive_done3;
    wire stream_skip0,stream_skip1,stream_skip2,stream_skip3;
    wire pmap_turn0,pmap_turn1,pmap_turn2,pmap_turn3;
    wire pmap_consume0,pmap_consume1,pmap_consume2,pmap_consume3;
    wire output_done0,output_done1,output_done2,output_done3;
    wire uses_bit0,uses_bit1,uses_bit2,uses_bit3;
    wire output_grant0,output_grant1,output_grant2,output_grant3;
    wire [63:0] out_value0,out_value1,out_value2,out_value3;
    wire out_valid0,out_valid1,out_valid2,out_valid3;
    wire [63:0] recv_value;
    wire take;

    assign in_ready=(state==PMAP)||
                    (lane_state0==3'd3)||(lane_state1==3'd3)||
                    (lane_state2==3'd3)||(lane_state3==3'd3);
    assign take=in_valid&in_ready;
    assign pmap_load=(state==PMAP)&&take&&in_byte[7];

    assign receive_allow0=(field_index0==expected_recv_field)&&(lane_state0==3'd3);
    assign receive_allow1=(field_index1==expected_recv_field)&&(lane_state1==3'd3);
    assign receive_allow2=(field_index2==expected_recv_field)&&(lane_state2==3'd3);
    assign receive_allow3=(field_index3==expected_recv_field)&&(lane_state3==3'd3);

    assign pmap_turn0=(field_index0==expected_recv_field);
    assign pmap_turn1=(field_index1==expected_recv_field);
    assign pmap_turn2=(field_index2==expected_recv_field);
    assign pmap_turn3=(field_index3==expected_recv_field);

    assign output_grant0=(lane_state0==3'd6)&&(expected_field==field_index0);
    assign output_grant1=(lane_state1==3'd6)&&(expected_field==field_index1);
    assign output_grant2=(lane_state2==3'd6)&&(expected_field==field_index2);
    assign output_grant3=(lane_state3==3'd6)&&(expected_field==field_index3);

    assign pmap_pop=pmap_consume0||pmap_consume1||pmap_consume2||pmap_consume3;

    wire recv_take;
    assign recv_take=(in_valid&&receive_allow0)||(in_valid&&receive_allow1)||
                     (in_valid&&receive_allow2)||(in_valid&&receive_allow3);
    assign field_ascii0=control_word0[75];
    assign field_ascii1=control_word1[75];
    assign field_ascii2=control_word2[75];
    assign field_ascii3=control_word3[75];
    assign recv_is_ascii=(receive_allow0&&field_ascii0)||(receive_allow1&&field_ascii1)||
                         (receive_allow2&&field_ascii2)||(receive_allow3&&field_ascii3);

    vli_receiver u_recv(
        .clk(clk),
        .rst(rst),
        .in_valid(recv_take),
        .is_ascii(recv_is_ascii),
        .in_byte(in_byte),
        .out_value(recv_value),
        .out_valid()
    );

    fast_pmap u_pmap(
        .clk(clk),
        .rst(rst),
        .in_byte(in_byte),
        .load(pmap_load),
        .pop(pmap_pop),
        .stop(pmap_flag)
    );

    smt_ram u_smt_ram(
        .clk(clk),
        .en(1'b0),
        .waddr(3'd0),
        .win(76'd0),
        .raddr1(field_index0),
        .raddr2(field_index1),
        .raddr3(field_index2),
        .raddr4(field_index3),
        .rin1(control_word0),
        .rin2(control_word1),
        .rin3(control_word2),
        .rin4(control_word3)
    );

    fast_sequencer#(.STEP(3'd4)) u_seq0(
        .clk(clk), .rst(rst), .start(pmap_load), .done(output_done0),
        .start_index(3'd0), .last_index(3'd4), .field_index(field_index0)
    );
    fast_sequencer#(.STEP(3'd1)) u_seq1(
        .clk(clk), .rst(rst), .start(pmap_load), .done(output_done1),
        .start_index(3'd1), .last_index(3'd1), .field_index(field_index1)
    );
    fast_sequencer#(.STEP(3'd1)) u_seq2(
        .clk(clk), .rst(rst), .start(pmap_load), .done(output_done2),
        .start_index(3'd2), .last_index(3'd2), .field_index(field_index2)
    );
    fast_sequencer#(.STEP(3'd1)) u_seq3(
        .clk(clk), .rst(rst), .start(pmap_load), .done(output_done3),
        .start_index(3'd3), .last_index(3'd3), .field_index(field_index3)
    );

    fast_lane_core u_lane0(
        .clk(clk), .rst(rst), .start(pmap_load),
        .in_valid(in_valid), .in_byte(in_byte),
        .receive_allow(receive_allow0), .output_grant(output_grant0),
        .pmap_flag(pmap_flag), .pmap_turn(pmap_turn0),
        .control_word(control_word0), .field_index(field_index0), .last_index(3'd4),
        .recv_value(recv_value),
        .state(lane_state0), .receive_done(receive_done0), .stream_skip(stream_skip0),
        .output_done(output_done0), .uses_bit(uses_bit0), .pmap_consume(pmap_consume0),
        .out_value(out_value0), .out_valid(out_valid0)
    );
    fast_lane_core u_lane1(
        .clk(clk), .rst(rst), .start(pmap_load),
        .in_valid(in_valid), .in_byte(in_byte),
        .receive_allow(receive_allow1), .output_grant(output_grant1),
        .pmap_flag(pmap_flag), .pmap_turn(pmap_turn1),
        .control_word(control_word1), .field_index(field_index1), .last_index(3'd1),
        .recv_value(recv_value),
        .state(lane_state1), .receive_done(receive_done1), .stream_skip(stream_skip1),
        .output_done(output_done1), .uses_bit(uses_bit1), .pmap_consume(pmap_consume1),
        .out_value(out_value1), .out_valid(out_valid1)
    );
    fast_lane_core u_lane2(
        .clk(clk), .rst(rst), .start(pmap_load),
        .in_valid(in_valid), .in_byte(in_byte),
        .receive_allow(receive_allow2), .output_grant(output_grant2),
        .pmap_flag(pmap_flag), .pmap_turn(pmap_turn2),
        .control_word(control_word2), .field_index(field_index2), .last_index(3'd2),
        .recv_value(recv_value),
        .state(lane_state2), .receive_done(receive_done2), .stream_skip(stream_skip2),
        .output_done(output_done2), .uses_bit(uses_bit2), .pmap_consume(pmap_consume2),
        .out_value(out_value2), .out_valid(out_valid2)
    );
    fast_lane_core u_lane3(
        .clk(clk), .rst(rst), .start(pmap_load),
        .in_valid(in_valid), .in_byte(in_byte),
        .receive_allow(receive_allow3), .output_grant(output_grant3),
        .pmap_flag(pmap_flag), .pmap_turn(pmap_turn3),
        .control_word(control_word3), .field_index(field_index3), .last_index(3'd3),
        .recv_value(recv_value),
        .state(lane_state3), .receive_done(receive_done3), .stream_skip(stream_skip3),
        .output_done(output_done3), .uses_bit(uses_bit3), .pmap_consume(pmap_consume3),
        .out_value(out_value3), .out_valid(out_valid3)
    );

    assign out_valid=out_valid0||out_valid1||out_valid2||out_valid3;
    assign out_value=out_valid0?out_value0
                    :out_valid1?out_value1
                    :out_valid2?out_value2
                    :out_value3;

    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE;
            expected_field<=3'd0;
            expected_recv_field<=3'd0;
            skip_pend0<=1'b0; skip_pend1<=1'b0; skip_pend2<=1'b0; skip_pend3<=1'b0;
        end
        else begin
            if(pmap_load) skip_pend0<=1'b0;
            else if(stream_skip0) skip_pend0<=1'b1;
            else if((field_index0==expected_recv_field)&&skip_pend0) skip_pend0<=1'b0;

            if(pmap_load) skip_pend1<=1'b0;
            else if(stream_skip1) skip_pend1<=1'b1;
            else if((field_index1==expected_recv_field)&&skip_pend1) skip_pend1<=1'b0;

            if(pmap_load) skip_pend2<=1'b0;
            else if(stream_skip2) skip_pend2<=1'b1;
            else if((field_index2==expected_recv_field)&&skip_pend2) skip_pend2<=1'b0;

            if(pmap_load) skip_pend3<=1'b0;
            else if(stream_skip3) skip_pend3<=1'b1;
            else if((field_index3==expected_recv_field)&&skip_pend3) skip_pend3<=1'b0;

            case(state)
                IDLE: begin
                    if(start)
                        state<=PMAP;
                end
                PMAP: begin
                    if(pmap_load) begin
                        state<=RUN;
                        expected_field<=3'd0;
                        expected_recv_field<=3'd0;
                    end
                end
                RUN: begin
                    if(output_done0||output_done1||output_done2||output_done3) begin
                        if(expected_field==3'd4)
                            expected_field<=3'd0;
                        else
                            expected_field<=expected_field+3'd1;
                    end

                    if((field_index0==expected_recv_field)&&(receive_done0|skip_pend0))
                        expected_recv_field<=expected_recv_field+3'd1;
                    else if((field_index1==expected_recv_field)&&(receive_done1|skip_pend1))
                        expected_recv_field<=expected_recv_field+3'd1;
                    else if((field_index2==expected_recv_field)&&(receive_done2|skip_pend2))
                        expected_recv_field<=expected_recv_field+3'd1;
                    else if((field_index3==expected_recv_field)&&(receive_done3|skip_pend3))
                        expected_recv_field<=expected_recv_field+3'd1;

                    if((lane_state0==3'd0)&&(lane_state1==3'd0)&&
                       (lane_state2==3'd0)&&(lane_state3==3'd0))
                        state<=IDLE;
                end
                default:
                    state<=IDLE;
            endcase
        end
    end
endmodule