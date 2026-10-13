// Rain: 10 columns of 6 drops; each drop is a 16 px streak 40-67 lines long, slanted by the wind, falling at
// its column's speed and wrapping. 60 points (100 overran the frame build).
let col = mod(in.x, 10);
let k = floor(in.x / 10);
let speed = 0.10 + col * 0.023;
let y = frac(k / 6 + col * 0.37 + in.t * speed) * 1000 - 40;
let len = 40 + col * 3;
out.vx = col * 192 + 80 + sin(in.t * 0.7 + col) * 30 - y * 0.15;
out.vy = y;
out.p0 = 1;
out.p1 = frac(k / 6 + col * 0.37 + in.t * speed);
out.p2 = 16;
out.p3 = len;
out.vdx = 0.15;
