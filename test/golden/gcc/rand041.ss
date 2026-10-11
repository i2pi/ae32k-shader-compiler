let a0 = step(smoothstep(in.mvx, in.k1, in.k0), max(tau, in.frame));
let a1 = smoothstep(sin(in.frame), max((in.t - 0.25), (in.y != 2)), 1920);
let a2 = (tau + (((0.25 * 1920) < (2 * in.k1)) || ((a0 <= a1) || tau)));
if ((-in.y <= -2)) { out.o0 = ((-in.heat * (0.5 - a0)) == cos((in.frame < 0.5))); }
