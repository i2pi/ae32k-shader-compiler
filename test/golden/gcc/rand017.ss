let a0 = abs((in.y + in.u));
let a1 = a0;
let a2 = !clamp(in.k0, step(-0.0001, smoothstep(0.0001, in.u, pi)), step(sqrt(pi), mod(a1, tau)));
out.o0 = !in.mvx;
if (((0 != in.x) % mod(in.k1, in.y))) { out.o1 = in.v; }
out.o2 = 100;
