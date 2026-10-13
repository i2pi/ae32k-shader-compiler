// Timing calibration: four static rectangles 1, 8, 22 and 47 px wide at x = 300, 700, 1100, 1500, rows 300..499,
// to fit the fast-path op cost (the narrowest span the rasteriser can draw).
out.vx = 300 + in.x * 400;
out.vy = 300;
out.p0 = 1;
out.p2 = 1 + 7 * in.x * (1 + in.x) / 2 + step(2.5, in.x) * 4;
out.p3 = 200;
