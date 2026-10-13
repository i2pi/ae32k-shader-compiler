// OSD sprite 0 alpha per cell (with `imcu canvas` on): p0 = 0..1 -> alpha 0..15.
@out a osd_s0_alpha
out.a = in.p0 * 16;
