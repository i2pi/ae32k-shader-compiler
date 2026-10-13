// Timing calibration: six static rectangles 1, 6, 12, 18, 24 and 30 px wide at x = 200 + 300 i, rows 300..499:
// the widths the fast and pad-only op paths draw.
out.vx = 200 + in.x * 300;
out.vy = 300;
out.p0 = 1;
out.p2 = max(in.x * 6, 1);
out.p3 = 200;
