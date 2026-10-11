let a0 = abs(atan2((!tau <= 3.75), -(in.y || 2)));
let a1 = ((atan2(a0, 7) && min(a0, 1920)) / (min(in.u, 2) || (a0 >= 1)));
out.o0 = lerp(2, -(0.5 == in.y), ((0 < 2) / frac(a0)));
out.o1 = a0;
out.o2 = min(7, step(0.0001, a1));
if (!(in.h != 2)) { out.o3 = pi; }
