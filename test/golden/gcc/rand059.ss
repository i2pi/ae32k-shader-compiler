let a0 = !step(pi, tau);
let a1 = (1 == in.mvx);
out.o0 = sqrt((mod(2, noise(1, a1)) / a0));
out.o1 = max(sin(in.w), (in.u >= a0));
out.o2 = min(floor((0 > a1)), lerp(lerp(noise(0.001, in.frame), (pi >= pi), in.frame), 3.75, max(max(in.u, 0.25), abs(in.k3))));
a0 = a0;
out.o5 = a0 + out.o0;
