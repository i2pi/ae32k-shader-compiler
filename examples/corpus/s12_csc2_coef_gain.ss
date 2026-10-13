// Second output CSC: coefficient 0 as a gain that ripples, offset Y added by cell parameter p2.
@out c0 out0_csc2_c0
@out oy out0_csc2_oy
out.c0 = 1 + 0.3 * sin(in.v * 4 - in.t * 0.5);
out.oy = in.p2 * 600;
