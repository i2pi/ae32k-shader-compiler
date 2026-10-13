// OSD layer-4 palette entry 1 cycles through hues down the frame; the strobe applies after any change.
@out pr osd_pal1_r
@out pg osd_pal1_g
@out pb osd_pal1_b
@out _ osd_pal_strobe
let h = in.v * 2 + in.t * 0.1;
out.pr = 0.5 + 0.5 * sin(h);
out.pg = 0.5 + 0.5 * sin(h + 0.333);
out.pb = 0.5 + 0.5 * sin(h + 0.667);
