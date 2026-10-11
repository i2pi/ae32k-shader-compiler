let a0 = (3.75 % (cos(tau) <= in.h));
let a1 = !mod(0.001, pi);
let a2 = smoothstep((clamp(a0, tau, tau) && sin(2)), abs((7 >= in.mvx)), !(in.heat - in.mvx));
let a3 = 2;
out.o0 = (0.25 - 1920);
