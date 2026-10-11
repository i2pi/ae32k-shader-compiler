let col = mod(in.x, 2);
let sl = floor(in.x / 2);
out.vx = col * 960;
out.vy = sl * 80;
out.p0 = mod(col + sl, 2);
out.p3 = 80;
