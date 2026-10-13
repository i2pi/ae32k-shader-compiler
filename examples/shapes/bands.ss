// Line bands for per-line effects: 96 slabs of 11 lines with no width (p2 = 0: one write per line, no reset),
// p1 = slab phase 0..1 so the effect stage can vary along the frame.
out.vx = 0;
out.vy = in.x * 11;
out.p0 = 1;
out.p1 = in.x / 96;
out.p2 = 0;
out.p3 = 11;
