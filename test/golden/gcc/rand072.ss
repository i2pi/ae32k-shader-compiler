let a0 = in.u;
let a1 = ((in.mvx >= min(3.75, 2)) + 0.001);
let a2 = sign(in.k1);
out.o0 = -noise(1, a1);
if (((7 < in.w) < 1)) { out.o1 = (3.75 <= lerp(in.frame, 2, mod(a0, 3.75))); }
out.o2 = 2;
out.o3 = in.heat;
a0 = (in.frame >= (in.h < in.k0));
out.o5 = a0 + out.o0;
