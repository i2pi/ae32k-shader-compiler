let a0 = (step(0.25, 3.75) <= (in.h || 0.001));
let a1 = ((in.mvy / a0) + step(100, in.k2));
let a2 = sin((((in.k3 - 100) + (0.001 <= in.t)) / noise(frac(in.mvy), (a0 || in.h))));
if (atan2(floor(in.frame), (1 / 2))) { out.o0 = (frac(max(in.t, in.rnd)) == min(sign(3.75), (a1 || a2))); }
