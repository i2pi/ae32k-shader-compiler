// Output test-pattern force on G: the green channel is clamped to a per-line value inside two moving bands.
@out tp out0_tp_force_g
let b1 = 1 - smoothstep(0.0, 0.06, abs(in.p1 - frac(in.t * 0.12)));
let b2 = 1 - smoothstep(0.0, 0.06, abs(in.p1 - frac(in.t * 0.12 + 0.5)));
let on = step(0.5, max(b1, b2));
out.tp = on * (4096 + floor(in.p1 * 4095));
