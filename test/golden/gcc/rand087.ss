let a0 = in.k3;
if (abs(in.w)) { out.o0 = (a0 || smoothstep(pi, (in.rnd != a0), -in.k3)); }
out.o1 = (in.heat % in.v);
out.o2 = pi;
out.o3 = (-(sin(in.k2) && (pi > 0.001)) / lerp(frac((2 * in.rnd)), !sin(in.rnd), ((in.k1 || 2) + in.mvy)));
