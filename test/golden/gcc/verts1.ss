// verts1.ss: vertex stage. 48 points on two orbiting rings; each point carries its
// angle in p0 and its ring in p1 for the scan stage. Upload: shader.py verts1.ss --vert --osc
// then `imcu scan verts 48 470` and start the scan with a scan stage that uses in.p0/p1.
let i = in.x;                       // point index 0..n-1
let ring = floor(i / 24);           // 0 or 1
let a = (i - ring * 24) / 24 * tau + in.t * (0.4 + ring * 0.3) * (in.k0 + 1);
let r = 180 + ring * 220 + 60 * sin(in.t * 1.3 + i);
out.vx = 960 + r * cos(a) * 1.3;
out.vy = 540 + r * sin(a);
out.p0 = a;
out.p1 = ring;
