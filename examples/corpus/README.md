# Shader corpus (2026-10-11)

40 stages written as optimiser training material for `external/ae32k_shader_compiler`: 20 vertex stages
(`v*.ss`, `--vert`: in.x = point index, in.u = index/n; out vx vy px, p0..p3) and 20 scan stages (`s*.ss`,
`--scan`, each with an `@out` map onto a register the mid-frame sweep found responsive). The scan stages assume
the vertex stage supplies p0 (parity), p1..p2 (free parameters). Registers that wedge the input (0x0234/0x0235,
0x0800 bit 6) are not used; the MFC stages (s18) need the MFC latch mode set to immediate (0x0800 bits 5:4 = 0).
