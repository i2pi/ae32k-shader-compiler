// Horizontal peaking coefficient 0: strong on even cells, off on odd, with a time-varying bias.
@out pk in_peak_h0
out.pk = in.p0 * floor(1024 + 1000 * sin(in.t * 0.2)) + (1 - in.p0) * 76;
