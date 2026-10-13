// Write-controller CbCr swap on drifting bands: colour inverts on alternate stripes.
@out csw wmc_cbcr_swap
out.csw = step(0, sin(in.p1 * 8 + in.t * 0.8));
