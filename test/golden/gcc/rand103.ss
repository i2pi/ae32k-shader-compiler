let a0 = (abs(0.001) <= (tau - in.x));
let a1 = !7;
let a2 = (-in.mvy - (in.w != a0));
let a3 = a2;
out.o0 = pi;
if (in.x) { out.o1 = ((a3 * (in.u % 0.0001)) > (sign(1) % in.k2)); }
out.o2 = 0.001;
a0 = lerp((in.heat <= in.mvx), 0.0001, (in.v != 0.25));
out.o5 = a0 + out.o0;
