// A vertical bar sweeping across, its width a noise field down the frame: 64 bands of 15 lines, width and centre
// interpolated to the next band (vdx, vdw), so the bar's sides are continuous curves.
let c = frac(in.t * 0.182) * 2200 - 140;
let y0 = in.x * 15;
let w0 = 60 + noise(y0 / 264, in.t * 0.5) * 200;
let w1 = 60 + noise((y0 + 15) / 264, in.t * 0.5) * 200;
out.vx = c - w0 * 0.5;
out.vy = y0;
out.p0 = 1;
out.p1 = w0 / 260;
out.p2 = w0;
out.p3 = 15;
out.vdx = (w0 - w1) / 30;
out.vdw = (w1 - w0) / 15;
