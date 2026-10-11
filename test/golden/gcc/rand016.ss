let a0 = (((0.0001 >= in.k3) >= (0.0001 || 1)) < -mod(pi, 0.0001));
let a1 = in.k0;
let a2 = ((abs(noise(0.0001, a1)) - sign(abs(a0))) + ((sign(a1) != a1) >= -(in.t == in.k1)));
let a3 = min((tau || clamp(in.h, (a2 % in.v), !0.5)), (floor(0) + (a2 == smoothstep(in.rnd, in.t, 1920))));
out.o0 = in.mvx;
