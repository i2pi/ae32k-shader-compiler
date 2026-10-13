// Output digital CbCr swap (bit 4) flips every N lines where N shrinks toward the bottom.
@out dsw out0_cbcr_swap
let n = 60 - in.v * 50;
out.dsw = mod(floor(in.y / n), 2);
