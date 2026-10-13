// verts2.ss: a grid of 8 x 6 points, static unless the knobs add a ripple. Each point
// carries its cell parity in p0, column in p1, row in p2. k0 = ripple amplitude (px),
// k1 = ripple speed. Upload: shader.py verts2.ss --vert --osc ; then: imcu scan verts 48 160
let col = mod(in.x, 8);
let row = floor(in.x / 8);
let ph = (col + row) * 0.12 + in.t * in.k1 * 0.5;
out.vx = (col + 0.5) * 240 + in.k0 * sin(ph);
out.vy = (row + 0.5) * 180 + in.k0 * 0.75 * cos(ph * 1.3);
out.p0 = mod(col + row, 2);
out.p1 = col;
out.p2 = row;
