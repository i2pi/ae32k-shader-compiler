// scan1.ss: per-scanline colour. Bands of channel permutation scroll down the frame,
// a slow luma wave rides on the CSC gains, the OSD palette entry cycles.
// k0 = band height lines, k1 = scroll speed. Run: shader.py scan1.ss --scan --osc --knobs 60,1
// then `imcu scan start 2 1080 231`.
@out gr   0x1C0E 0xFFFF 0 gain      // output CSC row Y: three coefficients, one gain
@out gr   0x1C0F 0xFFFF 0 gain
@out gr   0x1C10 0xFFFF 0 gain
@out gg   0x1C11 0xFFFF 0 gain
@out gg   0x1C12 0xFFFF 0 gain
@out gg   0x1C13 0xFFFF 0 gain
@out gb   0x1C14 0xFFFF 0 gain
@out gb   0x1C15 0xFFFF 0 gain
@out gb   0x1C16 0xFFFF 0 gain
@out swap 0x0111 0x0700 8 raw       // input channel permutation 0..5
@out pr   0x1078 0x00FF 0 unit      // OSD layer-4 palette entry 1
@out pg   0x1079 0xFF00 8 unit
@out pb   0x1079 0x00FF 0 unit
@out _    0x107A 0 0x8001 strobe    // palette strobe after any change
let band = floor((in.y + in.t * (in.k1 + 1) * 200) / (in.k0 + 24));
out.swap = mod(band, 6);
let w = sin(in.y * 0.002 + in.t * 0.7);
out.gr = 1 + w * 0.6;
out.gg = 1 - w * 0.6;
out.gb = 1 + sin(in.y * 0.005 - in.t) * 0.4;
out.pr = 0.5 + 0.5 * sin(in.y * 0.01 + in.t * 2);
out.pg = 0.5 + 0.5 * sin(in.y * 0.01 + in.t * 2 + 0.33);
out.pb = 0.5 + 0.5 * sin(in.y * 0.01 + in.t * 2 + 0.66);
