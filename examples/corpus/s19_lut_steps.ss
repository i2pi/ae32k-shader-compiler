// 1D LUT step enables per line: step 1 on the top half, step 2 on the bottom, swapping with time.
@out s1 lut1d_step1
@out s2 lut1d_step2
let top = step(in.v, 0.5 + 0.4 * sin(in.t * 0.1));
out.s1 = top;
out.s2 = 1 - top;
