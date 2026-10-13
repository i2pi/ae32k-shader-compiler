// Random scatter that re-rolls per frame on top of a fixed grid: in.rnd is fresh per evaluation.
let col = mod(in.x, 8);
let row = floor(in.x / 8);
let jx = (in.rnd - 0.5) * in.k0 * 200;
let jy = (noise(in.u * 7, in.t) - 0.5) * 120;
out.vx = col * 240 + 120 + jx;
out.vy = row * 90 + jy;
out.p0 = step(0.5, in.rnd);
out.p3 = 40;
