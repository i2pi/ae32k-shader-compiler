// Lit sphere from the output stage's PIP area blend (Send 1, PIP stage 2, area 0): per line the area spans the disc's
// chord and its horizontal blend ramp starts at the value the light gives at the chord's left end, so the inside is a
// smooth linear shading (a crossfade into the PIP layer's picture), lit from a direction that turns with time.
// Ops (vertex stage pip/p00_bands3.ss, p0 = kind): 0 = x0, y0, x1 (index 0); 1 = mode word with the ramp start
// (index 4); 2 = ramp increment (index 20). Address words have bit 15 set: written as negative values (two's
// complement, whole-word field). Per-line value slopes in o8.. (x0, x1, start follow the chord between band ends).
// Vertex stage: pip/p02_sphere_bands.ss (bands on the sphere + an off band). k0 = extra light angle (turns), k1 = radius scale. Needs /send/1/pip/2 on (alpha 1) and area 0's y1 preset.
@out o0 send1.pip2.area_addr
@out o1 send1.pip2.area_data
@out o2 send1.pip2.area_data
@out o3 send1.pip2.area_data
let r = 0.28 * (1 + in.k1);
let cx = 960 + 300 * sin(in.t * 0.05);
let cy = 520;
let ph = in.t * in.k2 + in.k0;
let lc = cos(ph);
let ls = sin(ph);
let y0 = in.y;
let h = in.p3;
let u0 = (y0 - cy) / 1080;
let u1 = (y0 + h - cy) / 1080;
let d0 = sqrt(max(r * r - u0 * u0, 0)) * 1080;
let d1 = sqrt(max(r * r - u1 * u1, 0)) * 1080;
let rp = r * 1080;
let inc = floor(1900 * lc / rp + 0.5);
let s0 = clamp(2048 - inc * d0 + 1900 * ls * (u0 / r), 16, 4080);
let s1 = clamp(2048 - inc * d1 + 1900 * ls * (u1 / r), 16, 4080);
let m = 0 - 32767 - 1;
let k = in.p0;
let g = step(k, 0.5);
let st = step(0.5, k) * step(k, 1.5);
let ic = step(1.5, k);
out.o0 = m + st * 4 + ic * 20;
out.o1 = g * (cx - d0) + st * (s0 - 16384) * (1 - in.p1) + ic * inc;   // off band: mode word 0 (area disabled)
out.o2 = 0;
out.o3 = g * (cx + d0);
out.o9 = g * (d0 - d1) / h + st * (s1 - s0) / h * (1 - in.p1);
out.o11 = g * (d1 - d0) / h;
