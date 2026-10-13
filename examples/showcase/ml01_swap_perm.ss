// in_swap: Y/Cb/Cr permutation inside the shape; k2 picks the order (1..7), per pixel.
@out swap in_swap
out.swap = in.p0 * (in.k2 + 2);
