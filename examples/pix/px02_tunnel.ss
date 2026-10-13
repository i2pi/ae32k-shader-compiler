// Pixel shader for ddr/pix_runner.c: a tunnel. Rings run outwards from the panel centre, striped by angle; colour
// cycles with depth. out.o0 = Y, out.o1 = Cb, out.o2 = Cr. k0 = speed, k1 = stripe count.
let du = in.u - 0.5;
let dv = (in.v - 0.5) * 0.25;
let r = sqrt(du * du + dv * dv) + 0.01;
let z = 0.15 / r + in.t * (0.3 + in.k0);
let a = atan2(dv, du) * (4 + floor(in.k1 * 8));
let chk = step(0.5, frac(z)) * 0.5 + step(0.5, frac(a)) * 0.5;
out.o0 = clamp((0.25 + 0.7 * abs(chk - 0.5) * 2) * clamp(r * 4, 0, 1), 0, 1);
out.o1 = 0.3 * sin(z * 0.5);
out.o2 = 0.3 * cos(z * 0.37);
