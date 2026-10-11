let a0 = smoothstep(sin(mod(in.t, pi)), (mod(in.t, 0) > noise(pi, 0)), clamp((pi == in.v), sqrt(in.mvy), atan2(in.y, pi)));
let a1 = (2 >= in.rnd);
out.o0 = ((((tau > in.u) * 7) || sign(-0.5)) / (in.rnd / sin(0.0001)));
a0 = mod(floor(100), sin(a0));
out.o5 = a0 + out.o0;
