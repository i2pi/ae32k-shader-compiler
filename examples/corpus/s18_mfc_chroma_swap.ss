// MFC0 chroma swap (immediate latch mode) and output-invalid bit: swap by parity, blank a moving band.
@out cs mfc0_chroma_swap
@out inv mfc0_out_invalid
out.cs = in.p0;
out.inv = step(0.5, 1 - abs(in.v - frac(in.t * 0.15)) * 20);
