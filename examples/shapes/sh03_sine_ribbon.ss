// A 240 px ribbon whose centre follows a sine down the frame, scrolling with time: 64 bands of 15 lines, each
// band's edges run straight to the next band's (vdx), so the ribbon's sides are continuous.
let y0 = in.x * 15;
let c0 = 960 + sin(y0 / 528 + in.t * 0.4) * 600;
let c1 = 960 + sin((y0 + 15) / 528 + in.t * 0.4) * 600;
out.vx = c0 - 120;
out.vy = y0;
out.p0 = 1;
out.p1 = y0 / 960;
out.p2 = 240;
out.p3 = 15;
out.vdx = (c1 - c0) / 15;
