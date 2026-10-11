// frag3.ss: cell stage for verts3. The input channel permutation (the one register the MDIN
// applies per pixel) alternates by cell parity: 0 = as is, k2 (default 2) = a swapped order.
@out swap 0x0111 0x0700 8 raw   // digital input port 0: what the HDMI Return shows
out.swap = in.p0 * (in.k2 + 2);
