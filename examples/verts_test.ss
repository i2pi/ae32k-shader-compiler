// verts_test.ss: static 8 x 12 checker of 240 x 96 px cells (calibration target for the cell engine).
let col = mod(in.x, 8);
let sl = floor(in.x / 8);
out.vx = col * 240;
out.vy = sl * 96;
out.p0 = mod(col + sl, 2);
out.p3 = 96;
