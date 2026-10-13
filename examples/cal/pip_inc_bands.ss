// cal: 18 full-width bands of 60 lines; p0 = the band's PIP area-0 ramp increment (1 .. 18)
out.vx = 0;
out.vy = in.x * 60;
out.p0 = in.x + 1;
out.p2 = 0;
out.p3 = 60;
