// Output CSC offsets (add mode) make horizontal bands of lifted Y and shifted Cb per cell parity.
@out oy out0_csc_oy
@out ocb out0_csc_ocb
out.oy = in.p0 * 300 * in.k0;
out.ocb = (1 - in.p0) * 400;
