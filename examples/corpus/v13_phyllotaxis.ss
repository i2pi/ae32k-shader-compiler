// Golden-angle phyllotaxis: 40 diamond seeds (80 points: the frame build budget), seed i at angle i x 0.382 turns and radius sqrt(i / n), the
// pattern turning slowly and each seed pulsing. A diamond is two trapezoids (upper and lower half) with
// exact sloped edges (vdx, vdw). Geometry in fractions of the height; centre (0.889, 0.45).
let seed = floor(in.x / 2);
let pc = mod(in.x, 2);
let n = 40;
let a = seed * 0.381966 + in.t * 0.02;
let r = sqrt((seed + 0.5) / n) * 0.40;
let cx = 0.8889 + cos(a) * r;
let cy = 0.45 + sin(a) * r;
let d = 0.012 + 0.030 * r / 0.40 * (0.75 + 0.25 * sin(in.t * 1.3 + seed * 0.1));
let la = floor((cy - d) * 1080);
let lm = floor(cy * 1080);
let lb = floor((cy + d) * 1080);
let l0 = la * (1 - pc) + lm * pc;
let l1 = lm * (1 - pc) + lb * pc;
let lines = l1 - l0;
let ok = step(0.5, lines);
let ya = (l0 + 0.5) / 1080;
let yb = (l1 + 0.5) / 1080;
let hwa = max(d - abs(ya - cy), 0);
let hwb = max(d - abs(yb - cy), 0);
let m = max(lines, 1);
out.vx = (cx - hwa) * 1080;
out.vy = l0 * ok + 1124 * (1 - ok);
out.p0 = 1;
out.p1 = r / 0.40;
out.p2 = hwa * 2160 + 1;
out.p3 = m;
out.vdx = (hwa - hwb) * 1080 / m;
out.vdw = (hwb - hwa) * 2160 / m;
