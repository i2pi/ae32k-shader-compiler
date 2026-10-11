// verts3.ss: a rippling checkerboard as cells. 8 columns x 14 slivers of 80 lines = 112 points;
// each point is the left edge of a cell 80 lines tall (p3), so the vertical edges can wave with y.
// p0 = cell parity (240 x 160 px checker), p1 = column, p2 = sliver. k0 = ripple px (+40), k1 = speed.
// Upload: shader.py verts3.ss --vert --osc ; imcu scan verts 112 160 0 1 ; imcu scan start 1 1125 456 1 0 4
let col = mod(in.x, 8);
let sl = floor(in.x / 8);
let y = sl * 80;
let amp = in.k0 + 40;
out.vx = col * 240 + amp * sin(y * 0.012 + in.t * (in.k1 + 1.5) + col * 0.4);
out.vy = y;
out.p0 = mod(col + floor(sl / 2), 2);
out.p1 = col;
out.p2 = sl;
out.p3 = 80;
