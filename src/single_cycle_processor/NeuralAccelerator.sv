import risc_v_32_i_pkg::*;

module NeuralAccelerator (
    input  logic              clk_i,
    input  logic              reset_i,
    input  logic              load_enable_i,
    input  logic signed [7:0] operand_a_i,
    input  logic signed [7:0] operand_b_i,
    output logic signed [31:0] y
);
    logic signed [7:0] x1, w1, x2, w2;
    logic signed [15:0] prod1, prod2;
    logic signed [31:0] sum;
    logic load_second_pair;

    always_ff @(posedge clk_i or posedge reset_i) begin
        if (reset_i) begin
            x1 <= '0;
            w1 <= '0;
            x2 <= '0;
            w2 <= '0;
            load_second_pair <= 1'b0;
        end else if (load_enable_i) begin
            if (load_second_pair) begin
                x2 <= operand_a_i;
                w2 <= operand_b_i;
            end else begin
                x1 <= operand_a_i;
                w1 <= operand_b_i;
            end
            load_second_pair <= ~load_second_pair;
        end
    end

    always_comb begin
        prod1 = x1 * w1;
        prod2 = x2 * w2;
        sum   = 32'(prod1) + 32'(prod2);
        y     = (sum < 0) ? 32'sd0 : sum;
    end
endmodule