let a0 = (clamp(in.t, tau, 0) % pi);
let a1 = smoothstep((0.5 + in.y), (in.rnd && a0), in.v);
if (sign(mod(1920, a1))) { out.o0 = in.frame; }
out.o1 = in.rnd;
out.o2 = sign((a0 * a0));
