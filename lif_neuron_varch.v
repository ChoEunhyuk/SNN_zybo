`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: CHAT-GPT
// 
// Create Date: 2025/07/07 20:44:08
// Module Name: lif_neuron_varch
//////////////////////////////////////////////////////////////////////////////////


//------------------------------------------------------------------------------
// Module: lif_neuron_varch.v
// Description: Fully parameterized Leaky Integrate-and-Fire neuron (Verilog-2001)
//------------------------------------------------------------------------------
module lif_neuron_varch #(
    // Number of input channels (spikes) //입력되는 스파이크의 갯수
    parameter integer N_CHANNEL   = 4,  
    // Weight bit width (e.g. Q1.7 format) 
    //원래는 그렇지만, 정밀도를 희생하는 대신 뉴런 수를 늘리는 전략으로, 6b'xxxxxx(2진 6비트)를 써보는건 어떰? // 그럼 0.98438에서 1사이가 떠버림. 그냥 정수값써서 비트를 줄일 순 없나..
    parameter integer W_WIDTH     = 8,
    // Membrane voltage bit width (e.g. Q8.8 format)
    parameter integer V_WIDTH     = W_WIDTH * 2,
    // Leak coefficient bit width (e.g. Q0.8 format)
    parameter integer L_WIDTH     = 8,
    // Threshold bit width (e.g. Q8.8 format)
    parameter integer T_WIDTH     = L_WIDTH * 2,
    // Reset value for V_mem (e.g. Q8.8 format)
    parameter signed [V_WIDTH-1:0] RESET_VALUE = {V_WIDTH{1'b0}},
    // Address width for weight register (computed from N_CHANNEL)
    parameter integer ADDR_WIDTH  = clog2(N_CHANNEL)
)(
    input                         clk,        // System clock
    input                         rst_n,      // Async active-low reset

    // Incoming spikes (0 or 1)
    input  [N_CHANNEL-1:0]        spike_in,

    // Weight write interface
    input                         weight_wr,     
    input  [ADDR_WIDTH-1:0]       weight_addr,  //address of weight register
    input  signed [W_WIDTH-1:0]   weight_data, //이거 weight의 수를 채널수랑 연동시켜야함.

    // Runtime parameters
//    input  signed [L_WIDTH-1:0]   leak_coef,
    input  signed   leak_coef,
    input  signed [T_WIDTH-1:0]   threshold,

    // Output spike
    output reg                    spike_out,
    
    output reg signed[V_WIDTH-1:0]  V_mem

);

//------------------------------------------------------------------------------
// Function: clog2
// Compute ceiling(log2(value)) for address width
//------------------------------------------------------------------------------
function integer clog2;
    input integer value;
    integer i;
    begin
        clog2 = 0;
        for (i = value - 1; i > 0; i = i >> 1)
            clog2 = clog2 + 1;
    end
endfunction

    //------------------------------------------------------------------------------
    // Internal registers and wires
    //------------------------------------------------------------------------------
    // Weight storage: N_CHANNEL signed weights
    reg signed [W_WIDTH-1:0]     weight_reg [0:N_CHANNEL-1];
    // Membrane potential register
    //reg signed [V_WIDTH-1:0]     V_mem;   //declared already. see earlier lines

    // Multiplier outputs for each channel (sign-extended to V_WIDTH)
    wire signed [V_WIDTH-1:0]    mult_out [0:N_CHANNEL-1];

    //leak (multiply method ) : didnt work well
    //wire signed [V_WIDTH+L_WIDTH-1:0] leak_product;
    //assign leak_product = leak_coef * V_mem;

    //leak (shift method)

    //------------------------------------------------------------------------------
    // Generate multipliers: sign-extend weight and multiply by spike_in
    //------------------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < N_CHANNEL; i = i + 1) begin : MUL_LOOP
            wire signed [V_WIDTH-1:0] w_ext;
            assign w_ext = {{(V_WIDTH-W_WIDTH){weight_reg[i][W_WIDTH-1]}}, weight_reg[i]};
            assign mult_out[i] = w_ext * spike_in[i];
        end
    endgenerate

    //------------------------------------------------------------------------------
    // Combinational adder tree (summation of mult_out)
    //------------------------------------------------------------------------------
    reg signed [V_WIDTH-1:0] I_sum;
    integer j;
    always @(*) begin
        I_sum = {V_WIDTH{1'b0}};

        for (j = 0; j < N_CHANNEL; j = j + 1)
            I_sum = I_sum + mult_out[j];
    end

    //------------------------------------------------------------------------------
    // Sequential logic: weight load, NOleak + integrate, threshold & reset
    //------------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            V_mem     <= RESET_VALUE;
            spike_out <= 1'b0;
            for (j = 0; j < N_CHANNEL; j = j + 1)
                weight_reg[j] <= {W_WIDTH{1'b0}};
        end else begin
            if (weight_wr)
                weight_reg[weight_addr] <= weight_data;

            // Leak and integrate(multiply method)  //250711 NOT IN USE(unappropriate)
                //V_mem <= -leak_product[V_WIDTH-1:0] + I_sum;
            // leak and integrate(shift method) //현재 사용중인 leak 방법. 정밀도는 뺄셈보다는 낮지만 연산이 단순하고 구현이 쉬움
                V_mem <= V_mem - (V_mem>>>leak_coef) + I_sum;

            //Integrate //no leakage design 250710 //NOT IN USE
                //V_mem <= V_mem+I_sum;
                
            // Threshold check and spike generation
            if (V_mem >= threshold) begin
                spike_out <= 1'b1;
                V_mem      <= RESET_VALUE;
            end else begin
                spike_out <= 1'b0;
            end
        end
    end

endmodule

