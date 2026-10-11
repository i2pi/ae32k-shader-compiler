// Starting points, one per stage (from the compiler README's examples).
const templates = <String, (int, String)>{
  'Warp: ripple': (
    0,
    '''// ripple: concentric waves from the centre. k0 = amplitude px, k1 = speed (turns/s)
let du = in.u - 0.5;
let dv = (in.v - 0.5) * 0.5625;           // 1080/1920: circular in pixels
let r = sqrt(du * du + dv * dv) + 0.0005;
let a = (in.k0 + 2) * sin(r * 8 - in.t * (in.k1 + 0.5));
out.dx = a * du / r;                      // displacement in pixels
out.dy = a * dv / r;
'''
  ),
  'Scan: CSC gain rows': (
    1,
    '''// output CSC row gains per line: red fades with v, blue with time
@out gr out0_csc_y0
@out gr out0_csc_y1
@out gr out0_csc_y2
@out gb out0_csc_b0
@out gb out0_csc_b1
@out gb out0_csc_b2
out.gr = 0.5 + 0.5 * sin(in.v * 2 + in.t * 0.3);
out.gb = 0.5 + 0.5 * cos(in.v * 3 - in.t * 0.2);
'''
  ),
  'Vertex: checkerboard': (
    2,
    '''// 8 x 12 checker of 240 x 96 px cells; in.x = point index
let col = mod(in.x, 8);
let sl = floor(in.x / 8);
out.vx = col * 240;
out.vy = sl * 96;
out.p0 = mod(col + sl, 2);                // passed to the scan stage as in.p0
out.p3 = 96;
'''
  ),
  'Empty warp stage': (
    0,
    '''// in.u, in.v: 0..1 across the frame; out.dx, out.dy: displacement in pixels
out.dx = 0;
out.dy = 0;
'''
  ),
};
