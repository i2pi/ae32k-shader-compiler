let a0 = in.v;
let a1 = (step(((100 <= in.rnd) / in.x), in.mvx) == in.x);
let a2 = smoothstep(in.w, 7, in.heat);
out.o0 = (3.75 == in.v);
out.o1 = (sign(in.k0) + (in.heat - a2));
out.o2 = sin(!in.k3);
