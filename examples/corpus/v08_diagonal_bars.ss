// Diagonal bars sweeping across: x position advances with the row and the time, wrapping at the frame edge.
let row = floor(in.x / 8);
let col = mod(in.x, 8);
let x = mod(col * 240 + row * 60 + in.t * 200, 1920);
out.vx = x;
out.vy = row * 90;
out.p0 = mod(col, 2);
out.p3 = 90;
