// Inside the shape: swap; on the shape's lines the output dark-screen bit blinks with time (per line).
@out swap in_swap
@out dark out0_dark
out.swap = in.p0 * 2;
out.dark = in.p0 * step(0, sin(in.t * 3 + in.v * 4));
