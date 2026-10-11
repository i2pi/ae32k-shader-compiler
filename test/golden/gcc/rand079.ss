let a0 = mod(2, (min((in.mvy >= 2), (7 * 7)) * max(in.k1, (2 - in.y))));
let a1 = (sign((in.rnd * in.k1)) < ((a0 > in.k2) != -pi));
let a2 = (in.k3 * in.rnd);
out.o0 = abs(in.mvy);
