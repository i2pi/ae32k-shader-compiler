let a0 = (smoothstep(2, 0.001, 0.0001) || (100 >= 100));
let a1 = -sin(in.mvy);
let a2 = frac(0.25);
if ((1 > -in.u)) { out.o0 = 0; }
out.o1 = in.k2;
if (max(a0, frac(in.u))) { out.o2 = atan2(mod(in.y, !a0), mod(abs(in.mvx), in.t)); }
if (lerp(max(0, in.mvy), (100 == in.h), in.k1)) { out.o3 = in.w; }
