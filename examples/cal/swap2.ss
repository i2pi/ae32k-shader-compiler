// Timing calibration: the input channel swap written twice per op (two map entries on one output), to
// separate the per-write cost from the fixed per-op cost.
@out swap in_swap
@out swap in_swap
out.swap = in.p0 * 2;
