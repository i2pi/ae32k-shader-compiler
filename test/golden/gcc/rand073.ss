let a0 = sqrt((((in.rnd < in.mvx) + (in.frame / 0.5)) < cos(!7)));
let a1 = a0;
out.o0 = floor((noise(2, tau) + (0.0001 * in.h)));
out.o1 = abs((7 >= mod(max(a1, in.k2), (tau / 1920))));
out.o2 = !cos(in.y);
out.o3 = 0.25;
a0 = a0;
out.o5 = a0 + out.o0;
