// A ring from four arcs (outer left, inner left, inner right, outer right), 24 segments each (chord error under 1 px; 96 points keep the build inside the frame). Every segment is
// a set-only edge (no width): the outer-left and inner-right arcs switch the effect on (p0 = 1), the other two
// switch it off, so each line runs on - off - on - off. Edge x is the exact chord between integer lines
// (geometry in fractions of the height), sloped with vdx, so the arcs are evaluated on every line.
let n = 24;
let arc = floor(in.x / n);
let k = mod(in.x, n);
let ro = 0.40;
let ri = 0.22 + 0.08 * sin(in.t * 0.4);
let inner = step(0.5, arc) * (1 - step(2.5, arc));
let sx = step(1.5, arc) * 2 - 1;
let R = lerp(ro, ri, inner);
let fa = 0.45 - R * cos(k / n * 0.5);
let fb = 0.45 - R * cos((k + 1) / n * 0.5);
let la = floor(fa * 1080);
let lb = floor(fb * 1080);
let lines = lb - la;
let ok = step(0.5, lines);
let ya = (la + 0.5) / 1080 - 0.45;
let yb = (lb + 0.5) / 1080 - 0.45;
let xa = sqrt(max(R * R - ya * ya, 0));
let xb = sqrt(max(R * R - yb * yb, 0));
out.vx = 960 + sx * xa * 1080;
out.vy = la * ok + 1124 * (1 - ok);
out.p0 = 1 - mod(arc, 2);
out.p1 = R;
out.p3 = max(lines, 1);
out.vdx = sx * (xb - xa) * 1080 / max(lines, 1);
