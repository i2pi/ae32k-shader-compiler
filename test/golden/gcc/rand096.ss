let a0 = max(in.mvy, in.w);
let a1 = atan2(sign(min((a0 > in.rnd), in.frame)), 1);
out.o0 = sin(in.heat);
out.o1 = cos(sqrt(1920));
out.o2 = (in.mvx <= in.mvx);
out.o3 = -floor(clamp((in.k1 == in.rnd), (0.5 >= in.v), smoothstep(tau, 0.5, in.h)));
a0 = 1;
out.o5 = a0 + out.o0;
