let a0 = frac(sign(1920));
let a1 = !(0.5 || (atan2(a0, in.heat) <= smoothstep(0.0001, 0.25, 0.0001)));
let a2 = ((smoothstep(0.001, 0.5, in.frame) / (in.x - in.h)) + smoothstep(max(a0, in.rnd), in.mvy, (in.u <= 3.75)));
out.o0 = abs(in.x);
a0 = in.mvx;
out.o5 = a0 + out.o0;
