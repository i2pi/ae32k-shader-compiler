let a0 = in.k2;
let a1 = in.rnd;
let a2 = abs(a0);
out.o0 = sin(pi);
a0 = (noise(0.001, in.y) % sqrt(a2));
out.o5 = a0 + out.o0;
