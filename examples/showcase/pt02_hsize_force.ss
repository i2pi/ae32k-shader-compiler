// mfc_hsize_force: the forced line width inside the shape (partial: resamples the rest of the line).
@out hs mfc_hsize_force
out.hs = 16384 + 1920 - in.p0 * floor(200 + 300 * abs(sin(in.t * 0.5 + in.p1 * 2)));
