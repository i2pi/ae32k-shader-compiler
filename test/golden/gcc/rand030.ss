let a0 = !in.k0;
out.o0 = ((noise(max(in.u, in.k2), sqrt(7)) > cos(atan2(in.h, in.k0))) * noise(0.5, (atan2(in.rnd, in.frame) / in.k1)));
if (frac(in.h)) { out.o1 = sqrt(in.k3); }
out.o2 = ((frac((a0 % 0.001)) % sqrt(mod(in.w, in.u))) % (min((a0 * in.y), in.mvx) || in.mvy));
out.o3 = ((in.k3 % in.mvx) >= (100 == in.t));
