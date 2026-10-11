let a0 = mod(in.rnd, in.y);
let a1 = lerp(in.frame, 0.5, (min(a0, in.k1) * (tau == in.k2)));
let a2 = ((a0 == in.mvy) + in.mvx);
if (-(tau != in.u)) { out.o0 = sign(0.5); }
out.o1 = (clamp(sin(in.h), atan2(a1, 3.75), atan2(a0, 7)) - floor(clamp(in.w, 100, 100)));
