// Timing calibration: two static shapes with known edge slopes, rows 300..499.
// Point 0: left edge x = 600 (vertical), right edge 601 + 2 px per line (a right triangle).
// Point 1: left edge 1400 + 1 px per line, right edge 1801 - 1 px per line (a converging trapezoid).
out.vx = 600 + in.x * 800;
out.vy = 300;
out.p0 = 1;
out.p2 = 1 + in.x * 400;
out.p3 = 200;
out.vdx = in.x;
out.vdw = 2 - in.x * 4;
