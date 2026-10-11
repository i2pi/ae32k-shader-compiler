// frag1.ss: scan stage for vertex mode. At each vertex: flip the write-side CbCr
// swap on ring 1, and set the output CSC luma gain from the point's angle so the
// raster below each point carries a different brightness until the next point.
@out swap 0x0237 0x0080 7 raw       // write-controller CbCr swap (per line)
@out gy   0x1C0E 0xFFFF 0 gain
@out gy   0x1C0F 0xFFFF 0 gain
@out gy   0x1C10 0xFFFF 0 gain
out.swap = in.p1;
out.gy = 0.7 + 0.6 * (0.5 + 0.5 * sin(in.p0 + in.t));
