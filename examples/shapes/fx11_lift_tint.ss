// Output CSC Y offset lifts a band that sweeps down, with the Cb offset tinting it blue then warm.
@out oy out0_csc_oy
@out ocb out0_csc_ocb
let d = abs(in.p1 - frac(in.t * 0.15));
let band = 1 - smoothstep(0.02, 0.12, d);
out.oy = band * 700;
out.ocb = band * 900 * sin(in.t * 0.7);
