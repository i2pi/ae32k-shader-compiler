// Pixel shader for ddr/pix_p8.c (8-bit palette canvas): one value, out.o0 = 0..1, a palette index. A moving
// interference field of three waves; the runner rotates the palette on top. sin takes turns. k0 = wave speed.
let tt = in.t * (0.08 + in.k0);
let x = in.u - 0.5;
let y = (in.v - 0.5) * 0.45;
let f = sin(x * 1.3 + tt) + sin(y * 1.7 - tt * 0.8) + sin(sqrt(x * x + y * y) * 2.5 - tt * 1.2);
out.o0 = 0.5 + f * 0.16;
