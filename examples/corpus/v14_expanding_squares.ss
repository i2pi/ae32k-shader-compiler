// Nested squares that expand from the centre with the frame count; 4 points per square edge set.
let sq = floor(in.x / 4);
let side = mod(in.x, 4);
let s = mod(sq * 0.08 + in.frame * 0.004, 0.5);
let sx = step(0.5, mod(side, 2)) * 2 - 1;
let sy = step(1.5, side) * 2 - 1;
out.vx = 960 + sx * s * 1920;
out.vy = 540 + sy * s * 1080;
out.p0 = mod(sq, 2);
out.p2 = s;
out.p3 = 8;
