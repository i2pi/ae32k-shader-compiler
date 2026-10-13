// cal: 8 full-height columns, 240 px each, p0 = column / 7 (for per-pixel value-register tests)
let col = mod(in.x, 8);
let row = floor(in.x / 8);
out.vx = col * 240;
out.vy = row * 500;
out.p0 = col / 7;
out.p2 = 0;
out.p3 = 500;
