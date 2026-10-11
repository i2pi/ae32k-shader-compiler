let a0 = (((smoothstep(in.k3, tau, in.heat) + abs(in.k0)) && (in.k1 || mod(tau, tau))) > -frac((in.y < in.k0)));
let a1 = abs(in.mvx);
out.o0 = noise(step((in.frame % in.t), (0.25 >= in.heat)), (!100 && (in.t / 1)));
if (sin((in.heat == 0))) { out.o1 = !1; }
out.o2 = min((atan2(clamp(1, 0.25, 0.001), (1 * in.rnd)) * (mod(7, 1920) / step(in.k2, 0.25))), tau);
