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

import taiga_config::*;
import taiga_types::*;

/*
 *  FIFOs Not underflow/overflow safe.
 *  Intended for small FIFO depths.
 */
module taiga_fifo #(parameter DATA_WIDTH = 32, parameter FIFO_DEPTH = 4, parameter fifo_type_t FIFO_TYPE = NON_MUXED_INPUT_FIFO)
        (
        input logic clk,
        input logic rst,
        fifo_interface.structure fifo
        );

    (* ramstyle = "MLAB, no_rw_check" *) logic[DATA_WIDTH-1:0] lut_ram[FIFO_DEPTH-1:0];
    logic[DATA_WIDTH-1:0] shift_reg[FIFO_DEPTH-1:0];
    logic[DATA_WIDTH-1:0] shift_reg_new[FIFO_DEPTH-1:0];

    logic[$clog2(FIFO_DEPTH)-1:0] write_index;
    logic[$clog2(FIFO_DEPTH)-1:0] read_index;
    logic two_plus;

    genvar i;

    //implementation
    ////////////////////////////////////////////////////



    ////////////////////////////////////////////////////
    //LUT-RAM version
    generate if (FIFO_TYPE == LUTRAM_FIFO) begin
            ////////////////////////////////////////////////////
            //Occupancy Tracking
            one_hot_occupancy #(.DEPTH(FIFO_DEPTH)) occupancy_tracking
                (
                    .push(fifo.push), .pop(fifo.pop),
                    .early_full(fifo.early_full), .full(fifo.full),
                    .empty(fifo.empty), .early_empty(fifo.early_empty), .valid(fifo.valid), .early_valid(fifo.early_valid), .two_plus(two_plus), .*
                );

            always_ff @ (posedge clk) begin
                if (rst) begin
                    read_index <= '0;
                    write_index <= '0;
                end
                else begin
                    read_index <= read_index + fifo.pop;
                    write_index <= write_index + fifo.push;
                end
            end
            assign fifo.data_out = lut_ram[read_index];

            always_ff @ (posedge clk) begin
                if (fifo.push)
                    lut_ram[write_index] <= fifo.data_in;
            end

        end
    endgenerate
    ////////////////////////////////////////////////////
    //SRL version
    //Uses a read index 2x the size of the FIFO to allow for simpler status determination
    //FIFO valid starts at FIFO_DEPTH to allow fifo.valid to come from the index reg
    generate if (FIFO_TYPE == NON_MUXED_INPUT_FIFO) begin

            ////////////////////////////////////////////////////
            localparam SRL_DEPTH = FIFO_DEPTH+1;
            localparam SRL_DEPTH_W = $clog2(SRL_DEPTH);

            logic [SRL_DEPTH_W-1:0] srl_index;
            logic full;
            logic full_minus_one;
            logic more_than_one;
            logic one_entry;

            //On first write will roll over to [1,00...0]
            //Upper bit of srl_index indicates
            always_ff @ (posedge clk) begin
                if (rst) begin
                    srl_index[SRL_DEPTH_W-1] <= 0;
                    srl_index[SRL_DEPTH_W-2:0] <= '1;
                end else
                    srl_index <= srl_index + fifo.push - fifo.pop;
            end

            //Helper expressions
            assign full = fifo.valid && (srl_index[SRL_DEPTH_W-2:0] == (FIFO_DEPTH-1));
            assign full_minus_one = fifo.valid && (srl_index[SRL_DEPTH_W-2:0] == (FIFO_DEPTH-2));
            assign more_than_one = fifo.valid && (srl_index[SRL_DEPTH_W-2:0] != 0);
            assign one_entry = fifo.valid && (srl_index[SRL_DEPTH_W-2:0] == 0);

            assign fifo.valid = srl_index[SRL_DEPTH_W-1];
            assign fifo.empty = ~fifo.valid;

            always_ff @ (posedge clk) begin
                fifo.full = ~fifo.pop & ((fifo.push & full_minus_one) | full);
            end

            assign fifo.early_valid = fifo.push | (fifo.valid & ~fifo.pop) | more_than_one;
            assign fifo.early_empty = one_entry  & fifo.pop & ~fifo.push;
            assign fifo.early_full = fifo.full | (full_minus_one & fifo.push);

            always_ff @ (posedge clk) begin
                if (fifo.push)
                    shift_reg[0] <= fifo.data_in;
            end

            for (i=1 ; i < FIFO_DEPTH; i++) begin : taiga_fifo_shift_reg_gen
                always_ff @ (posedge clk) begin
                    if (fifo.push)
                        shift_reg[i] <= shift_reg[i-1];
                end
            end

            assign fifo.data_out = shift_reg[srl_index[SRL_DEPTH_W-2:0]];


        end
    endgenerate
    ////////////////////////////////////////////////////
    //Non-muxed output version
    generate if (FIFO_TYPE == NON_MUXED_OUTPUT_FIFO) begin
            ////////////////////////////////////////////////////

            always_ff @ (posedge clk) begin
                if (rst)
                    write_index <= 0;
                else
                    write_index <= write_index + fifo.push - fifo.pop;
            end

            assign fifo.data_out = shift_reg[0];

            for (i=0 ; i <FIFO_DEPTH; i++) begin : taiga_fifo_new_reg_non_muxed_gen
                always_comb begin
                    if (fifo.push && write_index == i)
                        shift_reg_new[i] =  fifo.data_in;
                    else
                        shift_reg_new[i] = shift_reg[i];
                end
            end

            always_ff @ (posedge clk) begin
                shift_reg[FIFO_DEPTH-1] <= shift_reg_new[FIFO_DEPTH-1];
            end

            for (i=0 ; i < FIFO_DEPTH-1; i++) begin : taiga_fifo_shift_reg_non_muxed_gen
                always_ff @ (posedge clk) begin
                    if (fifo.pop)
                        shift_reg[i] <= shift_reg_new[i+1];
                    else
                        shift_reg[i] <= shift_reg_new[i];
                end
            end

        end
    endgenerate

endmodule


