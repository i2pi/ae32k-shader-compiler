// frag2.ss: scan stage for verts2. Two fixed tints by cell parity through the output
// CSC Cb/Cr offsets (per-line registers): the tint written at a point holds from that
// line until the next point in raster order. k2 = tint strength (+0.5).
@out cb out0_csc_ocb
@out cr out0_csc_ocr
let s = (in.k2 + 0.5) * 3000;
let a = in.p0 * 2 - 1;             // -1 or +1 by cell parity
out.cb = a * s;
out.cr = -a * s;
