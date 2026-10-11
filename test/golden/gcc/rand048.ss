let a0 = ((in.x + sqrt(-0.0001)) * abs(((tau && in.t) >= atan2(in.mvx, 0.5))));
let a1 = floor((3.75 >= in.y));
let a2 = in.k0;
out.o0 = (1 || ((clamp(in.v, in.k0, a0) - max(a2, in.v)) * (clamp(in.k3, in.w, 0.25) == step(1, in.k2))));
out.o1 = floor((atan2((in.v != in.k2), (in.mvx * a2)) || 0.25));
if (in.k1) { out.o2 = in.v; }
out.o3 = ((in.k3 * in.k3) == 7);
