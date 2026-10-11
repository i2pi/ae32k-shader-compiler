let a0 = lerp(((pi <= in.k0) == (pi + in.y)), in.mvx, sin(sqrt(in.rnd)));
let a1 = min(7, (in.k1 % pi));
out.o0 = a1;
if (in.rnd) { out.o1 = --mod(100, 0.5); }
out.o2 = (!7 && !0.5);
if (!in.k3) { out.o3 = (sign((a0 == in.mvy)) <= clamp(0, in.frame, 0.0001)); }
a0 = abs((2 == in.rnd));
out.o5 = a0 + out.o0;
