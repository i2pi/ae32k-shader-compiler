let a0 = abs(1920);
let a1 = -abs(1920);
let a2 = in.k1;
if (in.mvx) { out.o0 = 0.5; }
out.o1 = ((in.k1 > 0) == smoothstep(2, pi, 100));
if ((in.k3 || !tau)) { out.o2 = (0.25 || in.mvy); }
out.o3 = (in.w + 0.001);
