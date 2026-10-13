// per line: output CSC offsets lift and tint the lines the shape covers (line-latched: the leftmost edge on a
// line decides the line's value), with the channel swap per pixel inside the shape. The tint's hue rolls
// down the frame with the edge's line (in.y) and with time.
@out swap in_swap
@out oy out0_csc_oy
@out ocb out0_csc_ocb
out.swap = in.p0 * 2;
out.oy = in.p0 * 200;
out.ocb = in.p0 * 600 * sin(in.t * 0.6 + in.y / 1080 * 3);
