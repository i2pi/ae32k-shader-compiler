// Pixel shader for tools/imcu/examples/ddr/pix_runner.c (scan slot): colour wheel rings. Evaluated at every 10th pixel
// of a 320x100 panel each frame (u, v = 0..1 over the panel). out.o0 = Y 0..1, out.o1 = Cb, out.o2 = Cr (-0.5..0.5).
// k0 = ring count, k1 = spin speed.
let du = in.u - 0.5;
let dv = (in.v - 0.5) * 0.3125;
let r = sqrt(du * du + dv * dv);
let a = atan2(dv, du) + in.t * (0.1 + in.k1);
out.o0 = 0.5 + 0.4 * sin(r * (6 + in.k0 * 20) - in.t * 0.5);
out.o1 = 0.35 * cos(a);
out.o2 = 0.35 * sin(a);
