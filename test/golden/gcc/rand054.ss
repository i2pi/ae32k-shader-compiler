let a0 = 0.001;
out.o0 = ((in.heat != in.mvy) || cos(pi));
if (noise(in.mvx, max(3.75, 1))) { out.o1 = in.y; }
if (!(in.y > 2)) { out.o2 = frac(-clamp(pi, a0, a0)); }
out.o3 = -in.k0;
