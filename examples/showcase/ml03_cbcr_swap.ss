// in_p0_ctl_lo: the input port control byte the sweep flipped (Cb/Cr order and the neighbouring bits), per pixel.
@out b in_p0_ctl_lo
out.b = in.p0 * 255;
