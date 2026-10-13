// Write-controller CbCr swap per line, toggled by a noise threshold that drifts with time.
@out sw wmc_cbcr_swap
out.sw = step(0.5, noise(in.v * 6, in.t * 0.5));
