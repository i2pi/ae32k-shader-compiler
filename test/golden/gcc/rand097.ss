let a0 = (sqrt(clamp(pi, 0.25, 0.25)) * ((in.w > 0.001) < (in.y < 3.75)));
if ((floor(0.001) - max(in.k2, in.frame))) { out.o0 = (((a0 + in.k2) == in.mvy) == smoothstep(sqrt(in.frame), (in.w - in.y), (0.5 != 0.0001))); }
out.o1 = step(max(2, 0.25), (3.75 - a0));
out.o2 = in.k1;
if (floor((in.h <= 0))) { out.o3 = !(sign(in.w) && 0); }
