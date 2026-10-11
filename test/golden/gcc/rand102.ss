let a0 = min(smoothstep(sin(pi), (sin(1) <= !1), clamp(pi, (0.25 || 1), (in.y >= tau))), in.h);
let a1 = smoothstep(in.mvy, in.w, lerp(7, step(a0, (in.rnd - a0)), 0));
let a2 = in.k2;
let a3 = in.k1;
if (in.v) { out.o0 = sqrt(((a2 != in.k1) < a3)); }
if (in.frame) { out.o1 = max(sign(in.t), (sign(0.001) || sqrt(tau))); }
