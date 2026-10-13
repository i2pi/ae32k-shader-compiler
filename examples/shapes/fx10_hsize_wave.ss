// Forced MFC horizontal size per line: the picture width breathes along a travelling sine (geometric, per line).
@out hs mfc_hsize_force
out.hs = 16384 + 1920 + floor(240 * sin(in.p1 * 3 + in.t * 0.6));
