let a0 = frac(1920);
let a1 = (clamp((in.y == in.w), in.rnd, mod(3.75, in.k0)) > abs((in.mvy < 1)));
out.o0 = clamp((tau <= (in.frame * in.y)), (in.x - in.k1), (in.rnd % min(2, in.y)));
if (!(a0 || in.w)) { out.o1 = 1; }
if (clamp((in.k0 < in.u), frac(in.rnd), 1)) { out.o2 = max(smoothstep(min(3.75, in.mvx), sin(100), 0.001), cos(100)); }
