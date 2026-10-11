let a0 = (0.5 / sin(!floor(in.rnd)));
let a1 = ((in.k2 + 1) - clamp(in.x, 0, 100));
let a2 = ((!in.y || (in.w % in.h)) == sign(a1));
out.o0 = (in.u && cos(a0));
out.o1 = min((0.5 >= 0.0001), (in.h <= 0.0001));
