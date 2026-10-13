// Selective colour: enable and region-display bits, with the cos-theta register swept down the frame.
@out en out0_selcol_en
@out region out0_selcol_region
@out th out0_selcol_costh
out.en = 1;
out.region = step(0.5, in.p0);
out.th = floor(2048 + 2000 * cos(in.v + in.t * 0.1));
