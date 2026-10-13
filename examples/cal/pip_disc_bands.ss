// cal: a disc in 6-line bands over lines 0..995 (166 points; lines outside the disc close the area) for the PIP area blend: per band p0 = chord left x, p1 = chord right x (the area's x0, x1);
// one full-width cell per band (only the line matters: the area registers are written at the line's first edge).
let r = 0.28;
let y0 = in.x * 6;
let u = (y0 + 3 - 540) / 1080;
let d = sqrt(max(r * r - u * u, 0)) * 1080;
let inside = step(1, d);
out.vx = 0;
out.vy = y0;
out.p0 = (960 - d) * inside + 1919 * (1 - inside);
out.p1 = (960 + d) * inside + 1919 * (1 - inside);
out.p2 = 0;
out.p3 = 6;
