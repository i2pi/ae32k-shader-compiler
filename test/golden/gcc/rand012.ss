let a0 = (pi > noise((in.k3 > in.t), abs(pi)));
out.o0 = smoothstep(in.k2, in.mvx, in.mvy);
out.o1 = floor(a0);
