// A zigzag path across the frame: x triangle wave against the row index, animated phase.
let row = floor(in.x / 8);
let col = mod(in.x, 8);
let tri = abs(frac(row * 0.1 + in.t * 0.1) * 2 - 1);
out.vx = col * 240 + tri * 200 - 100;
out.vy = row * 90;
out.p0 = mod(col + row, 2);
out.p1 = tri;
out.p3 = 90;
