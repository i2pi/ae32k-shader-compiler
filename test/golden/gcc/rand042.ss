let a0 = !in.mvy;
let a1 = floor(in.t);
let a2 = (a0 - !in.heat);
out.o0 = 100;
if (floor((in.y < 7))) { out.o1 = a2; }
out.o2 = (clamp(clamp(7, in.t, (100 < 7)), ((in.v <= a1) >= atan2(in.rnd, in.frame)), abs(mod(2, a0))) % 0.0001);
out.o3 = (step(a0, in.x) != (0.5 == pi));
a0 = frac((in.k3 || in.t));
out.o5 = a0 + out.o0;
