let a0 = (max(tau, pi) != in.w);
let a1 = frac((-in.w >= sin(3.75)));
let a2 = (max(max((0.5 * pi), in.mvx), abs((in.mvx != in.frame))) > (((7 % 0.001) > !in.mvy) >= 0.5));
let a3 = min(((0.001 < 0.001) % (in.y + in.x)), (smoothstep(a1, in.rnd, in.x) <= -in.t));
if ((0 <= (in.rnd / a0))) { out.o0 = mod(max((in.mvy <= in.mvx), 2), -0.0001); }
out.o1 = sin((mod((a0 < 1), in.frame) - (cos(a3) || (in.mvx > 0.001))));
out.o2 = (!(in.mvy - (3.75 % in.k2)) / (noise(sin(0.5), !0.25) < (in.x + 1)));
if (0.0001) { out.o3 = pi; }
a0 = sqrt(0.0001);
out.o5 = a0 + out.o0;
