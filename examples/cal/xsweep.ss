// Edge-placement test: 40 bands of 20 lines (rows 100..899). In band b, two 300 px rectangles start at
// x = 400 + 0.37 b and x = 1200 + 0.37 b: four edges per line whose ideal positions step by 0.37 px per band.
// Per-row captures show quantisation (steps across bands) and per-line jitter (spread inside a band). 80 points.
let b = floor(in.x / 2);
let k = mod(in.x, 2);
out.vx = 400 + k * 800 + b * 0.37;
out.vy = 100 + b * 20;
out.p0 = 1;
out.p2 = 300;
out.p3 = 20;
