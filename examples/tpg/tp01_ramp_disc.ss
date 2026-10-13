// Input test pattern inside the shape: the input port's own pattern generator (0x013D) switched on at the cell edges.
// Pre-write 0x013D = 0x8000 | pattern (0x8002 horizontal ramp, 0x8003 vertical ramp); the cells toggle the enable.
@out tp in_tp_en
out.tp = in.p0;
