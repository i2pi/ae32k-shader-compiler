// The sine ribbon in 6-line bands (132 points, rows 240..1032) for line-latched (hold) registers,
// which take one value per cell: finer bands = a smoother edge.
let y0 = 240 + in.x * 6;
let c0 = 960 + sin(y0 / 528 + in.t * 0.4) * 600;
out.vx = c0 - 120;
out.vy = y0;
out.p0 = 1;
out.p2 = 240;
out.p3 = 6;
