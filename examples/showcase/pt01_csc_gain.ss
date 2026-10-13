// in_csc_c0..c3: input CSC coefficients scaled inside the shape (partial: shows where the picture has colour).
@out c0 in_csc_c0
@out c1 in_csc_c1
@out c2 in_csc_c2
@out c3 in_csc_c3
let g = 1 + in.p0 * (0.5 + 0.5 * sin(in.t * 0.7 + in.p1 * 3));
out.c0 = g;
out.c1 = 2 - g;
out.c2 = g;
out.c3 = 2 - g;
