// Soft wavy wipe from the PIP area blend: a full-width horizontal ramp on every line whose start follows a sine down
// the frame and slides with time; past full the ramp wraps, so the picture is crossed by soft stripes with one hard
// edge each. Start values interpolate between the band ends (value slope), so the stripes are smooth curves.
// Vertex stage pip/p00_bands3.ss. k0 = ramp steepness (increment per px), k1 = wave amplitude scale.
@out o0 send1.pip2.area_addr
@out o1 send1.pip2.area_data
@out o2 send1.pip2.area_data
@out o3 send1.pip2.area_data
let m = 0 - 32767 - 1;
let k = in.p0;
let g = step(k, 0.5);
let st = step(0.5, k) * step(k, 1.5);
let ic = step(1.5, k);
let inc = 3 + floor(in.k0 * 8);
let a = 1500 * (1 + in.k1);
let s0 = 2048 + a * sin(in.y / 900 + in.t * 0.12) + mod(in.t * 600, 4096);
let s1 = 2048 + a * sin((in.y + in.p3) / 900 + in.t * 0.12) + mod(in.t * 600, 4096);
let w0 = mod(s0, 4096);
let w1 = w0 + (s1 - s0);
out.o0 = m + st * 4 + ic * 20;
out.o1 = g * 0 + st * (w0 - 16384) + ic * inc;
out.o2 = 0;
out.o3 = g * 1919;
out.o9 = st * (w1 - w0) / in.p3;
