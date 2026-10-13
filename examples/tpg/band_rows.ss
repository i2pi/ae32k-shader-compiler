// Test shape: full-width cells over rows 400..699 (72 bands of 15 lines; bands outside have p0 = 0). For telling
// line-latched registers (a band shows) from frame-latched ones (nothing shows).
let y0 = in.x * 15;
let inside = step(400, y0) * (1 - step(700, y0));
out.vx = 0;
out.vy = y0 * inside + 1124 * (1 - inside);
out.p0 = inside;
out.p2 = 1919 * inside;
out.p3 = 15 * inside + 1 - inside;
out.vdx = 0;
out.vdw = 0;
