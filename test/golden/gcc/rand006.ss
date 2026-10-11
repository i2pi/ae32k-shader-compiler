let a0 = 1920;
let a1 = sin((noise(0.25, 0.5) != 0.0001));
let a2 = (lerp(0.0001, floor((a0 || in.mvx)), max(in.k0, in.k1)) > atan2(a0, !cos(pi)));
let a3 = in.mvx;
out.o0 = in.k3;
if ((clamp(in.x, 3.75, 0.0001) % (7 * 0))) { out.o1 = in.y; }
out.o2 = a2;
out.o3 = -in.h;
