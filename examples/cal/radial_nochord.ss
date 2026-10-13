// Radial gradient: 5 concentric rings around a moving centre, in bands of 40 lines, 10 cells per band (the left and
// right end of each ring's chord, trapezoids evaluated on every line). Inside ring k the level is 3k+3; leaving a
// ring returns to the outer ring's level (0 outside). A ring is left out of a band where its chord is under 30 px
// wide (edges closer than ~15 px snap). 200 points (20 bands).
let band = floor(in.x / 10);
let j = mod(in.x, 10);
let k = floor(j / 2);
let side = mod(j, 2);
let cx = 960 + 420 * sin(in.t * 0.08);
let cy = 560 + 60 * sin(in.t * 0.11);
let R = 380 * (5 - k) / 5;
let y0 = cy - 400 + band * 40;
let yt = floor(cy - R) + 1;
let yb = cy + R;
let ys = max(y0, yt);
let ye = min(y0 + 40, yb);
let h = max(ye - ys, 1);
let d0 = sqrt(max(R * R - (ys - cy) * (ys - cy), 0));
let d1 = sqrt(max(R * R - (ye - cy) * (ye - cy), 0));
let inside = step(0.5, ye - ys);
let sg = 1 - 2 * side;
out.vx = cx - sg * d0;
out.vy = ys * inside + 1124 * (1 - inside);
out.p0 = (1 - side) * (3 * k + 3) + side * 3 * k;
out.p2 = 0;
out.p3 = floor(ye - ys + 0.99) * inside + 1 - inside;
out.vdx = (sg * (d0 - d1)) / h * inside;
