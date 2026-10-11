let a0 = 0.25;
let a1 = mod(a0, in.v);
let a2 = lerp(((in.w >= 0.001) < cos(in.mvx)), abs(max(a0, in.w)), pi);
let a3 = floor(in.t);
if (((a3 < in.x) * (in.k1 <= a2))) { out.o0 = sign((in.u * abs(in.u))); }
if (frac(1)) { out.o1 = step((floor(a3) < 1920), cos((a3 * in.frame))); }
if (lerp(tau, smoothstep(in.rnd, 1, in.t), lerp(a2, in.u, in.frame))) { out.o2 = in.heat; }
out.o3 = ((in.heat % a3) * in.k2);
