// Lissajous figure, 3:2, drifting phase; cells shrink toward the ends of the parameter.
let s = in.u * 1 + in.t * 0.05;
out.vx = 960 + sin(s * 3) * 800;
out.vy = 540 + sin(s * 2 + in.k1) * 440;
out.p0 = step(0.5, frac(in.u * 4));
out.p1 = sin(s * 3);
out.p3 = 16 + abs(sin(s)) * 48;
