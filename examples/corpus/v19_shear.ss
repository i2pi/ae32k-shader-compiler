// An 8 x 10 grid sheared into a V: column lines lean by k px per line, one way above the middle and the other way
// below (vdx), k animated. The right column closes the line.
let col = mod(in.x, 8);
let row = floor(in.x / 8);
let k = sin(in.t * 0.2) * in.k0 * 0.5;
let y0 = row * 96;
let dir = step(4.5, row) * 2 - 1;
out.vx = col * 240 + k * abs(y0 - 480);
out.vy = y0;
out.p0 = mod(col + row, 2);
out.p1 = k;
out.p2 = step(6.5, col) * 240;
out.p3 = 96;
out.vdx = k * dir;
