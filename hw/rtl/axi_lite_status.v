`timescale 1ns/1ps
`default_nettype none

module axi_lite_status (
    input  wire                         aclk                       ,
    input  wire                         aresetn                    ,
    input  wire                         ddr_calib_done             ,
    input  wire          [  11: 0]      s_awaddr                   ,
    input  wire                         s_awvalid                  ,
    output wire                         s_awready                  ,
    input  wire          [  31: 0]      s_wdata                    ,
    input  wire          [   3: 0]      s_wstrb                    ,
    input  wire                         s_wvalid                   ,
    output wire                         s_wready                   ,
    output wire          [   1: 0]      s_bresp                    ,
    output reg                          s_bvalid                   ,
    input  wire                         s_bready                   ,
    input  wire          [  11: 0]      s_araddr                   ,
    input  wire                         s_arvalid                  ,
    output wire                         s_arready                  ,
    output reg           [  31: 0]      s_rdata                    ,
    output wire          [   1: 0]      s_rresp                    ,
    output reg                          s_rvalid                   ,
    input  wire                         s_rready
);

reg [31:0] scratch;
integer i;

assign s_awready = ~s_bvalid & s_wvalid;
assign s_wready  = ~s_bvalid & s_awvalid;
assign s_bresp   = 2'b00;
assign s_arready = ~s_rvalid;
assign s_rresp   = 2'b00;

always @(posedge aclk) begin
    if (!aresetn) begin
        scratch  <= 32'd0;
        s_bvalid <= 1'b0;
        s_rvalid <= 1'b0;
        s_rdata  <= 32'd0;
    end else begin
        if (s_bvalid && s_bready) begin
            s_bvalid <= 1'b0;
        end

        if (s_awvalid && s_wvalid && s_awready && s_wready) begin
            if (s_awaddr[11:2] == 10'd2) begin
                for (i = 0; i < 4; i = i + 1) begin
                    if (s_wstrb[i]) begin
                        scratch[i*8 +: 8] <= s_wdata[i*8 +: 8];
                    end
                end
            end
            s_bvalid <= 1'b1;
        end

        if (s_rvalid && s_rready) begin
            s_rvalid <= 1'b0;
        end

        if (s_arvalid && s_arready) begin
            case (s_araddr[11:2])
                10'd0:   s_rdata <= 32'h51444d41;
                10'd1:   s_rdata <= {31'd0, ddr_calib_done};
                10'd2:   s_rdata <= scratch;
                10'd3:   s_rdata <= 32'h00010000;
                default: s_rdata <= 32'd0;
            endcase
            s_rvalid <= 1'b1;
        end
    end
end

endmodule

`default_nettype wire
