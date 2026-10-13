// Even points form a coarse grid, odd points a fine grid offset by half a cell and moving the other way.
let odd = mod(in.x, 2);
let i = floor(in.x / 2);
let col = mod(i, 8);
let row = floor(i / 8);
let drift = in.t * 30;
out.vx = col * 240 + odd * 120 + (odd * 2 - 1) * drift;
out.vy = row * 180 + odd * 90;
out.p0 = odd;
out.p3 = 90 - odd * 45;
