// scan1.ss: per-scanline colour. Bands of channel permutation scroll down the frame,
// a slow luma wave rides on the CSC gains, the OSD palette entry cycles.
// k0 = band height lines, k1 = scroll speed. Run: shader.py scan1.ss --scan --osc --knobs 60,1
// then `imcu scan start 2 1080 231`.
@out gr out0_csc_y0   // output CSC row Y: three coefficients, one gain
@out gr out0_csc_y1
@out gr out0_csc_y2
@out gg out0_csc_g0
@out gg out0_csc_g1
@out gg out0_csc_g2
@out gb out0_csc_b0
@out gb out0_csc_b1
@out gb out0_csc_b2
@out swap in_swap   // input channel permutation 0..5
@out pr osd_pal1_r   // OSD layer-4 palette entry 1
@out pg osd_pal1_g
@out pb osd_pal1_b
@out _ osd_pal_strobe   // palette strobe after any change
let band = floor((in.y + in.t * (in.k1 + 1) * 200) / (in.k0 + 24));
out.swap = mod(band, 6);
let w = sin(in.y * 0.002 + in.t * 0.7);
out.gr = 1 + w * 0.6;
out.gg = 1 - w * 0.6;
out.gb = 1 + sin(in.y * 0.005 - in.t) * 0.4;
out.pr = 0.5 + 0.5 * sin(in.y * 0.01 + in.t * 2);
out.pg = 0.5 + 0.5 * sin(in.y * 0.01 + in.t * 2 + 0.33);
out.pb = 0.5 + 0.5 * sin(in.y * 0.01 + in.t * 2 + 0.66);
