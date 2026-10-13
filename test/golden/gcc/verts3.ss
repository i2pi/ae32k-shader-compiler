// verts3.ss: a rippling checkerboard as cells. 8 columns x 12 slivers of 96 lines = 96 points;
// each point is the left edge of a cell 96 lines tall (p3), so the vertical edges wave with y.
// Cheap on purpose (no sin): a triangle wave, so the per-frame build fits the frame's tail.
// p0 = cell parity (240 x 192 px checker), p1 = column, p2 = sliver. k0 = ripple px, k1 = speed.
// Upload: shader.py verts3.ss --vert --osc ; imcu scan verts 96 160 0 1 50482 384 ; imcu scan start 1 1000 456 1 0 65535
// (verts: n ecost 0 fill=1 period-offset(32768+Q8 loop cost) phase-iterations; start: ... lph=65535 = continuous)
let col = mod(in.x, 8);
let sl = floor(in.x / 8);
let ph = frac(sl * 0.125 + in.t * in.k1 * 0.25 + col * 0.05);
let tri = abs(ph * 2 - 1) * 2 - 1;
out.vx = col * 240 + in.k0 * tri;
out.vy = sl * 96;
out.p0 = mod(col + floor(sl / 2), 2);
out.p1 = col;
out.p2 = sl;
out.p3 = 96;
