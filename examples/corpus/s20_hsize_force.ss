// Forced MFC horizontal size per line: the picture width breathes with a sine, enable bit set.
@out hs mfc_hsize_force
let w = 1536 + floor(300 * sin(in.v * 2 + in.t * 0.3));
out.hs = 16384 + w;
