// Input CSC offsets G and Y per line: a slow vertical gradient plus a flicker from the frame counter.
@out og in_csc_og
@out oy in_csc_oy
let flick = mod(in.frame, 2) * 100;
out.og = in.v * 500 + flick;
out.oy = (1 - in.v) * 300;
