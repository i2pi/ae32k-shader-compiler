// Vertical-drift test: 40 bands of 20 lines (rows 100..899), each with the same two 300 px rectangles at x = 400 and
// 1200: any change of edge x down the frame is line-period or timing drift, not geometry. 80 points.
let b = floor(in.x / 2);
let k = mod(in.x, 2);
out.vx = 400 + k * 800;
out.vy = 100 + b * 20;
out.p0 = 1;
out.p2 = 300;
out.p3 = 20;
