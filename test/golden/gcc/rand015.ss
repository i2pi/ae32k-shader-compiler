let a0 = (3.75 * cos(in.w));
out.o0 = 0.5;
out.o1 = !lerp(step((in.frame != 1920), min(100, in.mvy)), 2, in.y);
