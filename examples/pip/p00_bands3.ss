// PIP area driver bands: 25 bands of 40 lines (lines 0..999), three cells per band at x = 0, 24, 48 (p0 = 0, 1, 2:
// the op kind for the scan stage: area geometry, ramp start, ramp increment). One full-width cell each: only the
// line matters, the area registers are written at the line's first edges. 75 points.
let band = floor(in.x / 3);
let k = mod(in.x, 3);
out.vx = k * 24;
out.vy = band * 40;
out.p0 = k;
out.p2 = 0;
out.p3 = 40;
