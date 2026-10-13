// cal: PIP area register write pair per edge: o0 = address write strobe (bit 15 onto the preloaded index), o1 = data
@out o0 send1.pip2.area_wr
@out o1 send1.pip2.area_val
out.o0 = 1;
out.o1 = in.p0;
