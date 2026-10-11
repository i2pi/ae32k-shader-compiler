let a0 = ((smoothstep(in.h, pi, in.h) && smoothstep(pi, in.u, in.k0)) % -step(in.k2, 0.0001));
let a1 = in.mvx;
let a2 = in.t;
out.o0 = (a2 > in.k0);
a0 = clamp(!in.t, sin(in.k1), clamp(tau, in.rnd, 0.001));
out.o5 = a0 + out.o0;
