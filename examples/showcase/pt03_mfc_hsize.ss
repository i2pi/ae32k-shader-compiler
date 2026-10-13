// mfc0_out_hsize: MFC output width inside the shape (partial; latch mode set to immediate by the harness).
@out w mfc0_out_hsize
out.w = 1920 - in.p0 * floor(100 + 500 * abs(sin(in.t * 0.4 + in.p1 * 2)));
