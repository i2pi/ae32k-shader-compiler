let a0 = (in.heat && pi);
let a1 = smoothstep(in.w, 7, mod(sqrt((0.25 / a0)), 7));
let a2 = (in.t && a1);
let a3 = ((0.5 <= sqrt((100 - in.w))) > -atan2(!in.rnd, (a2 * a2)));
out.o0 = 100;
out.o1 = ((in.k0 >= in.k0) || (in.y / tau));
out.o2 = clamp(in.k0, 0.001, (lerp((in.u / in.k0), !tau, !0) <= ((a3 || 0) / sign(in.u))));
out.o3 = frac(in.k2);
