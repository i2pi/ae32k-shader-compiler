// Each column is a vertical sine wave with its own phase; cells are short so the wave reads as a curve.
let col = mod(in.x, 8);
let k = floor(in.x / 8);
let ph = k * 0.07 + col * 0.125 + in.t * 0.3;
out.vx = col * 240 + 60 + sin(ph) * 90;
out.vy = k * 80;
out.p0 = mod(k, 2);
out.p1 = sin(ph);
out.p3 = 20;
