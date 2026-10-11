let a0 = atan2(0.5, 1);
let a1 = max(in.k0, (!a0 == in.rnd));
let a2 = (!(in.k2 / in.k0) >= ((in.frame != in.mvy) != in.t));
let a3 = lerp(smoothstep(in.heat, a1, in.k2), !in.h, (0.001 + 0.25));
out.o0 = tau;
a0 = ((in.k0 > in.rnd) / (in.x <= tau));
out.o5 = a0 + out.o0;
