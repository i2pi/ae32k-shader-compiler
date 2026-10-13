// cal: PIP area 0 x0 / y0 / x1 per line: o0 = address strobe (bit 15 onto preloaded index 0), o1 = x0, o2 = y0, o3 = x1
@out o0 send1.pip2.area_wr
@out o1 send1.pip2.area_val
@out o2 send1.pip2.area_val
@out o3 send1.pip2.area_val
out.o0 = 1;
out.o1 = in.p0;
out.o2 = 0;
out.o3 = in.p1;
