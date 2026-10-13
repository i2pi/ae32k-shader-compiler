// frag1.ss: scan stage for vertex mode. At each vertex: flip the write-side CbCr
// swap on ring 1, and set the output CSC luma gain from the point's angle so the
// raster below each point carries a different brightness until the next point.
@out swap wmc_cbcr_swap   // write-controller CbCr swap (per line)
@out gy out0_csc_y0
@out gy out0_csc_y1
@out gy out0_csc_y2
out.swap = in.p1;
out.gy = 0.7 + 0.6 * (0.5 + 0.5 * sin(in.p0 + in.t));
