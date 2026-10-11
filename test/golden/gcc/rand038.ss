let a0 = noise(in.v, in.h);
let a1 = abs(a0);
out.o0 = sqrt(frac(0));
out.o1 = clamp(a1, in.w, in.k3);
out.o2 = 0.0001;
if ((sign(in.w) / sqrt(1))) { out.o3 = ((7 > smoothstep(in.u, 0.25, in.k2)) == -in.mvy); }
