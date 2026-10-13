// No swap: Y and Cb output offsets per line, so the shape reads as a brightness/colour band pattern.
@out oy out0_csc_oy
@out ocb out0_csc_ocb
out.oy = in.p0 * 500;
out.ocb = in.p0 * 700 * sin(in.v * 3 + in.t * 0.5);
