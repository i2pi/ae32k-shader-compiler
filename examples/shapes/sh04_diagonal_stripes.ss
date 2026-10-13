// Diagonal stripes: six parallelograms 200 px wide running the full height at 0.8 px per line, scrolling
// right and wrapping (stripes start off the left of the frame and are clipped per line). 6 points.
let x0 = frac(in.x / 6 + in.t * 0.104) * 2880 - 900;
out.vx = x0;
out.vy = 0;
out.p0 = 1;
out.p1 = in.u;
out.p2 = 200;
out.p3 = 956;
out.vdx = 0.8;
