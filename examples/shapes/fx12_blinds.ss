// Output dark-screen bit as venetian blinds whose pitch opens and closes with time.
@out dark out0_dark
let pitch = 2 + 6 * abs(sin(in.t * 0.2));
out.dark = step(0.5, frac(in.x / pitch + in.t * 0.5));
