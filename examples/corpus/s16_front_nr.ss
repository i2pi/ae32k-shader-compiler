// Front noise-reduction Y filter coefficient 0 swept with a triangle wave down the frame.
@out nr in_nr_y0
let tri = abs(frac(in.v * 3 + in.t * 0.1) * 2 - 1);
out.nr = floor(4096 + tri * 12000);
