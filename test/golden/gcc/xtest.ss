// xtest.ss: is the output CSC offset applied inside the line? Pattern mode, 2 points per
// line (imcu scan start 1 1080 462 2 200): the tint alternates with the point's column.
@out cb 0x1C18 0x3FFF 0 add
@out cr 0x1C19 0x3FFF 0 add
let a = mod(floor(in.u * 2), 2) * 2 - 1;
out.cb = a * 4000;
out.cr = -a * 4000;
