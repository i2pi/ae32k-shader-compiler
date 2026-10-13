// Bouncing cells: |sin| gives the bounce, higher columns bounce faster.
let col = mod(in.x, 8);
let row = floor(in.x / 8);
let b = abs(sin(in.t * (0.3 + col * 0.05) + row * 0.1));
out.vx = col * 240;
out.vy = 980 - b * (900 - row * 60);
out.p0 = mod(col + row, 2);
out.p1 = b;
out.p3 = 40;
