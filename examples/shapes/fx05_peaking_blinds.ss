// Horizontal peaking strength per line, high inside the shape's lines, with the write CbCr swap on every 8th line.
@out pk in_peak_h0
@out csw wmc_cbcr_swap
out.pk = 76 + in.p0 * 1900;
out.csw = step(0.5, frac(in.y * 0.125));
