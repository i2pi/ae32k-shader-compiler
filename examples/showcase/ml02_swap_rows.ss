// in_swap: a different permutation on every cell row (p1 = row phase from the vertex stage), per pixel.
@out swap in_swap
out.swap = in.p0 * (1 + mod(floor(in.p1 * 7), 7));
