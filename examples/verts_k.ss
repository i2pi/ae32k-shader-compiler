// verts_k.ss: knob-driven probe cells. Two columns per row: column 0 at x = 0 with value k6 (1 = swap; k2 is the scan stage's swap mode),
// column 1 at x = k5 with value 0. Rows of k1 lines from line k3, k4 rows on screen (the rest parked at the
// bottom, off the walk). With k5 = 960 a per-pixel boot shows a half/half frame; with k5 = 1919 the register
// is k2 during the active part of the band's lines and 0 everywhere else.
let col = mod(in.x, 2);
let sl = floor(in.x / 2);
let on = sl < in.k4;
out.vx = col * in.k5;
out.vy = on * (in.k3 + sl * in.k1) + (1 - on) * 1124;
out.p0 = (1 - col) * in.k6;
out.p3 = in.k1;
