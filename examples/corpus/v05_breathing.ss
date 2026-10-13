// An 8 x 10 grid that breathes about the centre; parity flips every half cycle. Rows tile exactly (each row ends
// where the next begins); the right column closes the line (p2), so nothing runs past the grid.
let col = mod(in.x, 8);
let row = floor(in.x / 8);
let s = 0.75 + 0.25 * sin(in.t * 0.25);
let y0 = floor(478 + (row * 96 - 480) * s);
let y1 = floor(478 + (row * 96 + 96 - 480) * s);
out.vx = 960 + (col * 240 - 960) * s;
out.vy = y0;
out.p0 = mod(col + row + step(0, sin(in.t * 0.25)), 2);
out.p1 = s;
out.p2 = step(6.5, col) * 240 * s;
out.p3 = max(y1 - y0, 1);
