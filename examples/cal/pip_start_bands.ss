// cal: PIP area 0 per band: op 0 = geometry (x0 300, y0 0, x1 1600), op 1 = mode word with ramp start = band * 160
// (bands from pip/p00_bands3.ss; op 2 writes increment 0). No value slopes: shows whether the start applies per line.
@out o0 send1.pip2.area_addr
@out o1 send1.pip2.area_data
@out o2 send1.pip2.area_data
@out o3 send1.pip2.area_data
let m = 0 - 32767 - 1;
let k = in.p0;
let g = step(k, 0.5);
let st = step(0.5, k) * step(k, 1.5);
let ic = step(1.5, k);
let s0 = floor(in.y / 40) * 160 + 40;
out.o0 = m + st * 4 + ic * 20;
out.o1 = g * 300 + st * (s0 - 16384);
out.o2 = 0;
out.o3 = g * 1600;
