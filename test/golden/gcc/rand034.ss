let a0 = (step(in.frame, in.k1) * sqrt(0.001));
let a1 = (in.k1 + (in.v == tau));
let a2 = (-a0 < in.frame);
out.o0 = ((a2 != 1) <= atan2(3.75, in.mvy));
out.o1 = frac(0.5);
out.o2 = smoothstep((((tau && in.v) % !a0) + mod(in.v, lerp(in.k3, a2, in.k3))), smoothstep(frac(100), (tau != (a1 / 0.0001)), floor((a1 >= pi))), (in.k1 / pi));
