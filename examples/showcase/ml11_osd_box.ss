// OSD simple box edges from the cells. DOES NOT WORK from the scan engine (2026-10-12): continuous writes to the box
// edge registers hide the box (it shows only once the writes stop). Kept as the reproduction case; see
// docs/MIDLINE_REGISTER_SWEEP.md (correction under 0x1059).
@out x0 osd_box_x0
@out x1 osd_box_x1
out.x0 = in.x;
out.x1 = in.x + in.p2;
