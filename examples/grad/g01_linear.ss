// Rotating linear gradient: 12 parallel straight boundaries, in bands of 250 lines (each band's edge runs straight
// to the next band's, so a boundary is one exact line down the frame). Right of boundary k the level is k+1 (spread
// over the 16-level scale). The angle rocks through +-35 degrees; boundaries leaving the frame are clamped to its
// edge. k0 = extra angle (turns), k1 = spacing scale. 48 points (4 bands: the build must fit the blanking).
let band = floor(in.x / 12);
let k = mod(in.x, 12);
let th = 0.1 * sin(in.t * 0.06) + in.k0;
let tn = sin(th) / cos(th);
let y0 = band * 250;
let c = 960 + (k - 5.5) * 150 * (1 + in.k1);
let b0 = clamp(c - (y0 - 540) * tn, 0, 1919);
let b1 = clamp(c - (y0 + 250 - 540) * tn, 0, 1919);
out.vx = b0;
out.vy = y0;
out.p0 = floor((k + 1) * 15 / 12 + 0.5);
out.p2 = 0;
out.p3 = 250;
out.vdx = (b1 - b0) / 250;
