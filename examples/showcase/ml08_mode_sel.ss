// in_mode_sel: input mode select changed inside the shape, per pixel (garbles the data path).
@out m in_mode_sel
out.m = in.p0 * (1 + floor(in.p1 * 3));
