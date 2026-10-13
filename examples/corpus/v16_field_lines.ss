// Points placed along the field lines of two poles: angle from atan2 picks the row, radius the column.
let col = mod(in.x, 8);
let row = floor(in.x / 8);
let a = row / 12 + in.t * 0.03;
let r = 0.05 + col * 0.055;
let dx = cos(a) * r;
let dy = sin(a) * r;
let ang = atan2(dy, dx + 0.2) - atan2(dy, dx - 0.2);
out.vx = 960 + dx * 1920 + ang * 100;
out.vy = 540 + dy * 1080;
out.p0 = mod(col, 2);
out.p1 = ang;
out.p3 = 30;
