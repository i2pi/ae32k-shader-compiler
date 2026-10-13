// Blank colour luma per cell (input CDC buffer 4, 0x1F2C) with the blank held on (pre-write 0x1F04 = 0x1000).
@out y cdc4_blank_y
out.y = in.p0 * 4095;
