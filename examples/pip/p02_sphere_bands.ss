// Bands for pip/p01_sphere.ss: 25 bands spanning the sphere at equal angle steps (thin bands at the poles, so the
// linear chord between band ends follows the circle) (same r, cy formulas as the scan stage), then one "off"
// band (p1 = 1) just below that disables the area (a zero-width area still shows): lines without cells keep the
// last write, so the area stays off until the next frame's first band. Three cells per band (p0 = op kind). 78 points.
let r = 0.28 * (1 + in.k1);
let cy = 520;
let rp = r * 1080;
let band = floor(in.x / 3);
let k = mod(in.x, 3);
let off = step(24.5, band);
let ya = floor(cy - rp * cos(band / 50));
let yb = floor(cy - rp * cos((band + 1) / 50));
out.vx = k * 24;
out.vy = ya * (1 - off) + floor(cy + rp + 1) * off;
out.p0 = k;
out.p1 = off;
out.p2 = 0;
out.p3 = max(yb - ya, 1) * (1 - off) + off;
