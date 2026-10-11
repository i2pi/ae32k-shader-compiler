let a0 = min((cos(sin(in.k3)) - (in.mvx >= -in.mvy)), (in.x > floor(in.h)));
out.o0 = (clamp(a0, (in.v - in.w), (0.5 >= in.u)) >= in.h);
out.o1 = ((-in.x * in.rnd) <= max(lerp(in.k3, in.x, 0.5), in.k3));
out.o2 = frac(a0);
out.o3 = (0.25 % in.w);
