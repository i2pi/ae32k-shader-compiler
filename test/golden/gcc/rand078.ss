let a0 = 3.75;
let a1 = sign(in.k0);
let a2 = (((in.mvy != -in.x) <= 0.25) <= sqrt(in.x));
if (lerp(in.k0, floor(in.heat), (0 >= in.mvx))) { out.o0 = a2; }
if (step((a1 * in.frame), mod(100, in.frame))) { out.o1 = noise(in.t, clamp((in.x * in.y), in.mvx, max(in.w, pi))); }
