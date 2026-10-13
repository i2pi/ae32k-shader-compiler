// Input CDC buffer 4 data blanking switched at the cell edges: the blank colour (0x1F2B..0x1F2D, preset) inside the shape.
@out bl cdc4_blank_en
out.bl = in.p0;
