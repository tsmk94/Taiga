/*
 * Copyright © 2017 Eric Matthews,  Lesley Shannon
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Initial code developed under the supervision of Dr. Lesley Shannon,
 * Reconfigurable Computing Lab, Simon Fraser University.
 *
 * Author(s):
 *             Eric Matthews <ematthew@sfu.ca>
 */


module div_radix2
        #(
        parameter C_WIDTH = 32
        )(
        input logic clk,
        input logic rst,
        input logic start,
        input logic ack,
        input logic [C_WIDTH-1:0] A,
        input logic [C_WIDTH-1:0] B,
        output logic [C_WIDTH-1:0] Q,
        output logic [C_WIDTH-1:0] R,
        output logic complete,
        output logic B_is_zero
        );

    logic terminate;

    logic [C_WIDTH:0] new_PR;
    logic [C_WIDTH:0] PR;

    logic [C_WIDTH-1:0] shift_count;
    logic [C_WIDTH-1:0] B_r;

    logic negative_sub_rst;

    //implementation
    ////////////////////////////////////////////////////
    assign new_PR = PR - {1'b0, B_r};
    assign negative_sub_rst = new_PR[C_WIDTH];

    //Shift reg for
    always_ff @ (posedge clk) begin
        shift_count[0] <= start;
        shift_count[31:1] <= shift_count[30:0];
    end

    always_ff @ (posedge clk) begin
        if (start) begin
            PR <= {{(C_WIDTH-2){1'b0}}, A[C_WIDTH-1]};
            Q <= {A[C_WIDTH-2:0], 1'b0};
            B_r <= B;
        end
        else if (~terminate) begin
            PR <= negative_sub_rst ? {PR[C_WIDTH-1:0], Q[C_WIDTH-1]} :
                {new_PR[C_WIDTH-1:0], Q[C_WIDTH-1]};
            Q <= {Q[C_WIDTH-2:0], ~negative_sub_rst};
        end
    end

    assign R = PR[C_WIDTH:1];

    always_ff @ (posedge clk) begin
        if (start)
            B_is_zero <= ~B[0];
        else  if (~terminate)
            B_is_zero <= B_is_zero & ~negative_sub_rst;
    end

    always_ff @ (posedge clk) begin
        if (rst)
            terminate <= 0;
        else begin
            if (start)
                terminate <= 0;
            if (shift_count[31])
                terminate <= 1;
        end
    end

    always_ff @ (posedge clk) begin
        if (rst)
            complete <= 0;
        else begin
            if (shift_count[31])
                complete <= 1;
            else if (ack)
                complete <= 0;
        end
    end

endmodule