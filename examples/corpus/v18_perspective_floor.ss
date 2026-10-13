// A floor grid in perspective: rows compress toward the horizon (1 / (1 + depth)), columns converge.
let col = mod(in.x, 8);
let row = floor(in.x / 8);
let depth = row * 0.5 + frac(in.t * 0.2) * 0.5;
let z = 1 / (1 + depth);
out.vx = 960 + (col - 3.5) * 240 * z;
out.vy = 300 + 780 * z;
out.p0 = mod(col + floor(depth), 2);
out.p2 = z;
out.p3 = 40 * z + 4;
