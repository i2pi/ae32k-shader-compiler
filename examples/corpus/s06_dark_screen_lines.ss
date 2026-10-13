// Output dark screen on alternate groups of lines: a per-line venetian blind whose pitch is a knob.
@out dark out0_dark
let pitch = 8 + in.k0 * 40;
out.dark = step(0.5, frac(in.y / pitch + in.t * 0.2));
