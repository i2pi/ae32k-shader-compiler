// scan2.ss: a pattern inside the line. Evaluated every 2nd line at 12 points across
// each line (imcu scan start 2 1080 231 12 15): the channel permutation changes
// mid-line so the frame becomes a drifting mosaic of swapped channels, and the
// CSC luma gain breathes diagonally. k0 = mosaic drift speed, k1 = diagonal tilt.
@out swap in_swap
@out gy out0_csc_y0
@out gy out0_csc_y1
@out gy out0_csc_y2
let cx = floor(in.u * 6 + in.t * (in.k0 + 0.5));
let cy = floor(in.v * 4 - in.t * 0.3);
out.swap = mod(cx + cy * 3, 6);
out.gy = 0.8 + 0.5 * sin(in.u * 6 + in.v * (in.k1 + 3) - in.t * 2);
