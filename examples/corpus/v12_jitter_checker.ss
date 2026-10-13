// Static checker with value-noise displacement; k0 scales the jitter, noise is smooth across the grid.
let col = mod(in.x, 8);
let row = floor(in.x / 8);
let nx = noise(col * 0.3, row * 0.3 + in.t * 0.1) - 0.5;
let ny = noise(col * 0.3 + 5, row * 0.3) - 0.5;
out.vx = col * 240 + nx * in.k0 * 100;
out.vy = row * 90 + ny * in.k0 * 60;
out.p0 = mod(col + row, 2);
out.p3 = 90;
