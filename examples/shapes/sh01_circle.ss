// A filled circle from 72 trapezoid bands of 15 lines: each band's left edge and width slope with the chord
// (vdx, vdw: px per line), so the edge is evaluated on every line. The band holding a pole starts at the
// circle's true top or bottom, so no band reaches outside the circle; bands outside it are parked off the frame. Geometry in fractions of the height.
let r = 0.28 + 0.06 * sin(in.t * 0.3);
let bh = 15;
let y0 = in.x * bh;
let yt = floor(540 - r * 1080) + 1;
let yb = 540 + r * 1080;
let ys = max(y0, yt);
let ye = min(y0 + bh, yb);
let h = max(ye - ys, 1);
let yy0 = (ys - 540) / 1080;
let yy1 = (ye - 540) / 1080;
let dx0 = sqrt(max(r * r - yy0 * yy0, 0));
let dx1 = sqrt(max(r * r - yy1 * yy1, 0));
let inside = step(0.5, ye - ys);
out.vx = 960 - dx0 * 1080;
out.vy = ys * inside + 1124 * (1 - inside);                // bands outside the circle go below the walk: no ops
out.p0 = inside;
out.p2 = (dx0 * 2160 + 1) * inside;
out.p3 = floor(ye - ys + 0.99) * inside + 1 - inside;           // the band stops at the circle's bottom (width never goes negative)
out.vdx = (dx0 - dx1) * 1080 / h * inside;
out.vdw = (dx1 - dx0) * 2160 / h * inside;
