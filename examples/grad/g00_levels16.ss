// 16-level scale from four per-pixel bits: in_swap values 0..3 (2 bits: none, Y<>Cb, Y<>Cr, Cb<>Cr), in_cbcr_swap,
// in_demux_c_first. (in_swap's top bit, msb<>lsb, turns the picture to noise: not used.) The vertex stage gives each
// cell its level in p0 (0..15); level 0 = the untouched picture. The levels are 16 distinct looks, not a brightness
// ramp: a 16-step palette for gradients along the line.
@out a in_swap
@out b in_cbcr_swap
@out c in_demux_c_first
let L = clamp(floor(in.p0 + 0.5), 0, 15);
out.a = mod(L, 4);
out.b = mod(floor(L / 4), 2);
out.c = floor(L / 8);
