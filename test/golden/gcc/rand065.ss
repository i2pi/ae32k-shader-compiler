let a0 = 3.75;
let a1 = (3.75 && in.heat);
let a2 = frac(floor(abs(in.w)));
let a3 = in.k0;
out.o0 = lerp(mod(in.v, a3), a2, (a2 + a3));
if ((cos(1) <= smoothstep(in.frame, 0.001, a3))) { out.o1 = sqrt(a1); }
if (sqrt(frac(in.k0))) { out.o2 = 2; }
out.o3 = in.rnd;
