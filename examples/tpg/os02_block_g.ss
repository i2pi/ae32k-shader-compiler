// OSD block (background box) colour green byte per cell: p0 = 0..1 -> 0..255 (box set up by the test harness).
@out g osd_block_g
out.g = in.p0 * 255;
