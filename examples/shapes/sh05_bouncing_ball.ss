// A ball (radius 162 px) bouncing and drifting: 28 bands of 12 lines from the ball's true top, each band's sides
// the exact chord between its first and last line (vdx, vdw). Geometry in pixels (r^2 fits Q16).
let R = 162;
let cy = 780 - abs(sin(in.t * 0.5)) * 560;
let cx = 960 + sin(in.t * 0.13) * 700;
let top = floor(cy - R) + 1;
let ys = top + in.x * 12;
let ye = min(ys + 12, cy + R);
let h = max(ye - ys, 1);
let a = ys - cy;
let b = ye - cy;
let dx0 = sqrt(max(R * R - a * a, 0));
let dx1 = sqrt(max(R * R - b * b, 0));
let on = step(0.5, ye - ys);
out.vx = cx - dx0;
out.vy = ys * on + 1124 * (1 - on);
out.p0 = 1;
out.p1 = in.x / 28;
out.p2 = 2 * dx0 + 1;
out.p3 = floor(h + 0.99);
out.vdx = (dx0 - dx1) / h;
out.vdw = 2 * (dx1 - dx0) / h;
