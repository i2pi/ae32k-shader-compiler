let a0 = lerp(((tau > frac(pi)) - min(1, in.x)), (frac((in.frame != in.k0)) > -in.heat), (lerp((0.5 + in.y), (7 <= pi), sqrt(in.x)) <= smoothstep(in.rnd, (0.25 % 100), (pi == 0.0001))));
if (atan2((in.heat == in.v), (a0 < tau))) { out.o0 = (in.t < (in.k2 != max(in.y, in.frame))); }
if ((!in.k1 - step(in.v, in.heat))) { out.o1 = 2; }
out.o2 = a0;
if (min((a0 > 1), abs(pi))) { out.o3 = in.y; }
a0 = frac(in.w);
out.o5 = a0 + out.o0;
