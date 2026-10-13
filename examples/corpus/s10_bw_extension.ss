// Black/white extension enable per line, gated by a sine so it pulses in bands.
@out bw out0_bw_ext
out.bw = step(0, sin(in.v * 5 + in.t * 0.4));
