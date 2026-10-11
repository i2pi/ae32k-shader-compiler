let a0 = in.h;
if (sqrt((a0 * 0.5))) { out.o0 = !in.y; }
out.o1 = clamp((!(in.k3 % 0) == -in.frame), 0.25, 0);
out.o2 = (cos(max(in.mvy, smoothstep(0.0001, in.mvx, in.k3))) < max(cos(7), (atan2(0.001, 7) != sqrt(in.u))));
