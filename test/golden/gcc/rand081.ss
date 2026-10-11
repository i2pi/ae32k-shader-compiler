let a0 = ((in.k3 > 7) == in.w);
let a1 = (mod(sign((a0 + 7)), ((100 && 100) > (in.rnd * in.heat))) || (sign(0.5) % clamp((a0 || 0), smoothstep(3.75, in.mvy, in.k2), lerp(2, 1, 0))));
let a2 = (in.k0 / 0.5);
out.o0 = !a0;
