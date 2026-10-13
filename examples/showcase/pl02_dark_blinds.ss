// per line: dark-screen blinds inside the shape's lines plus the swap.
@out swap in_swap
@out dark out0_dark
out.swap = in.p0 * 3;
out.dark = in.p0 * step(0.5, frac(in.y * 0.1 + in.t * 0.5));
