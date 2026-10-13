// 4:2:0 test pattern enable on lines where a value-noise field exceeds a knob threshold.
@out tp out0_tp420
out.tp = step(0.4 + in.k1 * 0.2, noise(in.v * 10, in.t * 0.3));
