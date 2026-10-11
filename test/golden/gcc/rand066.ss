let a0 = (noise(abs(0.5), in.v) / (-0.0001 + (7 * 100)));
let a1 = min(0, -in.u);
let a2 = sqrt(atan2((0.5 || in.mvy), max(in.mvy, in.heat)));
out.o0 = sin(((3.75 || cos(in.w)) < ((in.k1 || 1) && (in.t / 3.75))));
out.o1 = ((lerp((pi + in.k1), 0.001, lerp(0.0001, 1, in.k2)) - noise((a1 % a1), in.k3)) * (!-3.75 >= (sin(a1) * in.t)));
out.o2 = min(sign((in.heat + a0)), -in.k2);
out.o3 = 7;
a0 = 3.75;
out.o5 = a0 + out.o0;
