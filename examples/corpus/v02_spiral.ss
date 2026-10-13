// Points on an Archimedean spiral that slowly rotates; p0 = turn count, p2 = radius 0..1.
let i = in.u;
let a = i * 3 + in.t * 0.1;
let r = i * 0.45;
out.vx = 960 + cos(a) * r * 1920;
out.vy = 540 + sin(a) * r * 1080;
out.p0 = mod(floor(i * 6), 2);
out.p2 = r;
out.p3 = 24 + i * 60;
