// Timing calibration: four static rectangles, left edges at x = 200, 600, 1000, 1400 px and widths 100, 150,
// 200, 250 px, rows 300..499. Measure the captured edges against these to fit the write latency and the
// per-op cost the cell rasteriser charges.
out.vx = 200 + in.x * 400;
out.vy = 300;
out.p0 = 1;
out.p2 = 100 + in.x * 50;
out.p3 = 200;
