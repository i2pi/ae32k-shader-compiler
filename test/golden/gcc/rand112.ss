let a0 = !step((in.x < in.frame), floor(pi));
let a1 = in.x;
out.o0 = abs((max(cos(in.h), 2) % in.t));
out.o1 = (0 || 0.5);
out.o2 = (mod(step(frac(tau), floor(7)), (tau % smoothstep(in.k3, in.u, tau))) / clamp((in.k3 >= (in.w <= in.k0)), ((a1 < 3.75) || (pi || a1)), ((in.u < 0) < max(a1, in.k2))));
out.o3 = tau;
