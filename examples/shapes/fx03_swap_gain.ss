// Inside the shape: swap plus the output CSC Y gain pulsing per line (two registers per op).
@out swap in_swap
@out gy out0_csc_y0
out.swap = in.p0 * 3;
out.gy = 1 + in.p0 * 0.8 * sin(in.v * 6 + in.t);
