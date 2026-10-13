// verts_inv.ss: the static 8 x 12 checker with inverted parity (test of per-line/per-frame register latching).
let col = mod(in.x, 8);
let sl = floor(in.x / 8);
out.vx = col * 240;
out.vy = sl * 96;
out.p0 = mod(col + sl + 1, 2);
out.p3 = 96;
