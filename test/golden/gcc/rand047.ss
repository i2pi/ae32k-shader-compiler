let a0 = -floor(in.y);
let a1 = (0 < in.frame);
let a2 = smoothstep(((in.mvy != (in.t == a0)) >= in.w), abs((!a1 >= in.w)), min(noise(a0, (a1 % 1)), (sqrt(a0) + max(in.k2, in.frame))));
let a3 = in.u;
out.o0 = frac(in.mvx);
out.o1 = abs((in.h * mod((100 != in.k2), (1920 == 0.001))));
