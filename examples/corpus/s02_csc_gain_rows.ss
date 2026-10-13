// Output CSC row gains per line: red fades with v, blue with time, green steady.
@out gr out0_csc_y0
@out gr out0_csc_y1
@out gr out0_csc_y2
@out gb out0_csc_b0
@out gb out0_csc_b1
@out gb out0_csc_b2
out.gr = 0.5 + 0.5 * sin(in.v * 2 + in.t * 0.3);
out.gb = 0.5 + 0.5 * cos(in.v * 3 - in.t * 0.2);
