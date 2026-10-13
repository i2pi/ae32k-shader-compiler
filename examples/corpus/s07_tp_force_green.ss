// Force the green test-pattern value on lines inside a travelling band (enable bit + 12-bit value).
@out tp out0_tp_force_g
let band = smoothstep(0.0, 0.05, abs(in.v - frac(in.t * 0.1)));
out.tp = (1 - step(0.5, band)) * (4096 + floor(in.v * 4095));
