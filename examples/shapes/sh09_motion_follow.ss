// A disc that follows the motion in the picture: centred on the motion centroid (in.mvx, in.mvy, px; the frame
// centre when nothing moves), radius growing with the mean motion (in.heat). Needs `imcu scan motion` (heat grid
// from the input's frame ring). k0 scales the heat response. 72 trapezoid bands of 15 lines, as sh01_circle.
let r = 0.04 + clamp(in.heat * (2 + in.k0 * 20), 0, 0.22);
let cx = in.mvx;
let cy = in.mvy;
let bh = 15;
let y0 = in.x * bh;
let yt = floor(cy - r * 1080) + 1;
let yb = cy + r * 1080;
let ys = max(y0, yt);
let ye = min(y0 + bh, yb);
let h = max(ye - ys, 1);
let yy0 = (ys - cy) / 1080;
let yy1 = (ye - cy) / 1080;
let dx0 = sqrt(max(r * r - yy0 * yy0, 0));
let dx1 = sqrt(max(r * r - yy1 * yy1, 0));
let inside = step(0.5, ye - ys);
out.vx = cx - dx0 * 1080;
out.vy = ys * inside + 1124 * (1 - inside);
out.p0 = inside;
out.p2 = (dx0 * 2160 + 1) * inside;
out.p3 = floor(ye - ys + 0.99) * inside + 1 - inside;
out.vdx = (dx0 - dx1) * 1080 / h * inside;
out.vdw = (dx1 - dx0) * 2160 / h * inside;
