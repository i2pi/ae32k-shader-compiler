let a0 = noise(step(step(2, max(tau, in.v)), (step(0, 0.25) % (in.u % 100))), max((mod(in.v, in.h) * in.v), 0.5));
if ((sin(in.u) || (in.x >= in.frame))) { out.o0 = 0.5; }
if (smoothstep(cos(in.x), (in.k1 / 3.75), (in.k1 + 0.5))) { out.o1 = ((in.mvy > abs(3.75)) != noise(in.mvy, atan2(a0, in.k0))); }
out.o2 = (abs(in.mvy) + min(0.25, in.k3));
a0 = lerp(lerp(in.k0, a0, 0.25), (a0 / in.mvx), 0);
out.o5 = a0 + out.o0;
