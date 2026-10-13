// A diamond from two trapezoids (upper and lower half) whose sides slope exactly (vdx, vdw), sliding left and right.
// 2 points: in.x = 0 is the upper half, 1 the lower half.
let cx = 960 + sin(in.t * 0.2) * 500;
let hh = 420;
let hw = 420;
let lower = in.x;
out.vx = cx - hw * lower;
out.vy = 478 - hh + hh * lower;
out.p0 = 1;
out.p2 = 2 * hw * lower + 1;
out.p3 = hh;
out.vdx = (2 * lower - 1) * hw / hh;
out.vdw = (1 - 2 * lower) * 2 * hw / hh;
