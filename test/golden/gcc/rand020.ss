let a0 = in.k2;
if (in.heat) { out.o0 = (((0.25 / in.t) * (a0 + 1)) == 0.5); }
if ((abs(in.mvy) >= in.k2)) { out.o1 = (!clamp(a0, 0.25, in.k1) + max(min(0.001, in.x), atan2(in.heat, 0.5))); }
if (step(frac(in.k2), in.rnd)) { out.o2 = (max(pi, (a0 && in.frame)) == (sqrt(in.k2) + (in.w && tau))); }
