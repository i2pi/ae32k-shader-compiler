let a0 = min(in.u, (!in.u || (0.001 / in.k0)));
let a1 = 0.25;
let a2 = (step(min(lerp(0.5, in.y, 1920), (in.w != in.y)), a1) || (-(0.0001 == in.y) >= min(-in.y, noise(0.25, 100))));
let a3 = a2;
out.o0 = atan2((100 > a0), frac(!1));
if (in.k1) { out.o1 = (sqrt(a3) != sqrt((1 + a2))); }
