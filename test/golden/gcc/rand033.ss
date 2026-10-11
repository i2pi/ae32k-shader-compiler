let a0 = floor(in.mvy);
let a1 = cos(in.heat);
let a2 = 1920;
if (noise((0 / in.mvy), abs(in.frame))) { out.o0 = ((sign(0.5) - noise(a2, 3.75)) == (sign(tau) / mod(1, a0))); }
if (sqrt((pi <= in.rnd))) { out.o1 = !(step(in.k0, 0) % (1920 % a1)); }
