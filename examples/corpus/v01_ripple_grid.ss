// 8 x 10 grid whose cells bob on a travelling diagonal ripple. Each cell ends exactly where the cell below
// starts (no gaps), and its left edge slopes to the left edge of the cell below (vdx), so the column lines
// are continuous zig-zags. p0 = parity, p1 = ripple phase for the scan stage. k0 = ripple amplitude.
let col = mod(in.x, 8);
let row = floor(in.x / 8);
let r0 = sin((col + row) * 0.125 - in.t * 0.5);
let r1 = sin((col + row + 1) * 0.125 - in.t * 0.5);
let y0 = floor(row * 95 + r0 * in.k0 * 20 * step(0.5, row));
let y1 = floor((row + 1) * 95 + r1 * in.k0 * 20 * (1 - step(8.5, row)));
let lines = max(y1 - y0, 1);
out.vx = col * 240 + 120 + r0 * in.k0 * 40;
out.vy = y0;
out.p0 = mod(col + row, 2);
out.p1 = r0;
out.p3 = lines;
out.vdx = (r1 - r0) * in.k0 * 40 / lines;
