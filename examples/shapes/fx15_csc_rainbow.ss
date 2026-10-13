// Input CSC offsets G and Y per line: a slow rainbow of tints rolling down the frame.
@out og in_csc_og
@out oy in_csc_oy
out.og = 600 * sin(in.p1 * 2 + in.t * 0.3);
out.oy = 400 * cos(in.p1 * 2 + in.t * 0.3);
