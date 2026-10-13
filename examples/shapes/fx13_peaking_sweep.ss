// Horizontal peaking: razor sharp inside a band that sweeps, soft everywhere else.
@out pk in_peak_h0
let d = abs(in.p1 - frac(in.t * 0.1));
out.pk = 76 + (1 - smoothstep(0.03, 0.15, d)) * 2000;
