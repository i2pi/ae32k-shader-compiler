let a0 = ((-in.k0 * (pi * pi)) * 0.25);
let a1 = (-in.k2 > noise(in.frame, a0));
let a2 = (in.k2 >= 3.75);
out.o0 = in.h;
out.o1 = 0.25;
out.o2 = 0.5;
