// Input channel permutation by cell parity (per pixel): p0 from the vertex stage picks the order.
@out swap in_swap
out.swap = in.p0 * (in.k2 + 2);
