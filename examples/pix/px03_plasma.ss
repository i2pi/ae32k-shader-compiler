// Pixel shader (pix_osd.c / pix_runner.c, scan slot): a four-term colour plasma. u, v = 0..1 over the canvas; the
// hue turns with the field value, the luma follows it. sin/cos take turns. k0 = speed, k1 = spatial scale.
let s = 1 + in.k1 * 3;
let tt = in.t * (0.15 + in.k0);
let x = (in.u - 0.5) * s;
let y = (in.v - 0.5) * s * 0.5625;
let f = sin(x * 1.4 + tt) + sin(y * 1.9 - tt * 1.3) + sin((x + y) * 1.1 + tt * 0.7) + sin(sqrt(x * x + y * y) * 2.2 - tt * 1.1);
let h = f * 0.15 + tt * 0.05;
out.o0 = 0.45 + 0.1 * f;
out.o1 = 0.38 * cos(h);
out.o2 = 0.38 * sin(h);
