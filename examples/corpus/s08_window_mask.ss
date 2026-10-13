// Window-mask enable + colour per line: the enable nibble and the colour index are separate fields so each
// output stays inside the Q16 range (raw mode writes the integer part into the masked field).
@out en out0_winmask_en
@out col out0_winmask_col
out.en = step(0.5, in.p0) * 15;
out.col = floor(abs(in.p1) * 255);
