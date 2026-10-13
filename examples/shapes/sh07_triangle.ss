// A triangle: one trapezoid from a 1 px apex at the top to a 1000 px base, the apex sliding along the top.
// 1 point.
let ax = 960 + sin(in.t * 0.25) * 600;
let h = 860;
out.vx = ax;
out.vy = 40;
out.p0 = 1;
out.p2 = 1;
out.p3 = h;
out.vdx = (460 - ax) / h;
out.vdw = 999 / h;
