let a0 = in.frame;
let a1 = in.mvy;
out.o0 = (max(100, (-100 * clamp(in.rnd, a0, in.x))) >= floor(a0));
out.o1 = in.mvx;
out.o2 = min(3.75, pi);
out.o3 = ((in.mvx / 0.25) != step(in.frame, 0.25));
a0 = a1;
out.o5 = a0 + out.o0;
