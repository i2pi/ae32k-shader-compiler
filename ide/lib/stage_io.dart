// What each stage can read and write (docs/LANGUAGE.md "Inputs" / "Outputs"; the resident's
// hyb_main.c fills the inputs).
class StageItem {
  final String name, meaning;
  const StageItem(this.name, this.meaning);
}

// inputs per stage (docs/LANGUAGE.md "Inputs"; the resident's hyb_main.c fills them)
List<StageItem> stageInputs(int slot) => [
      if (slot == 2) ...const [
        StageItem('x', 'point index (0, 1, 2, ...)'),
        StageItem('u', 'index / point count, 0..1'),
      ] else ...const [
        StageItem('x', 'position in pixels'),
        StageItem('y', 'position in pixels'),
        StageItem('u', 'position across the frame, 0..1'),
        StageItem('v', 'position down the frame, 0..1'),
      ],
      const StageItem('t', 'seconds since the engine started'),
      const StageItem('frame', 'frame counter'),
      const StageItem('rnd', 'random 0..1, fresh per evaluation'),
      const StageItem('w', 'frame width, pixels'),
      const StageItem('h', 'frame height, pixels'),
      for (var k = 0; k < 8; k++)
        StageItem('k$k', 'knob $k (OSC /send/1/shader/k/$k)'),
      if (slot == 0) ...const [
        StageItem('heat', 'motion at the point (flow on), else 0'),
        StageItem('mvx', 'motion vector x (flow on), else 0'),
        StageItem('mvy', 'motion vector y (flow on), else 0'),
      ],
      if (slot == 1)
        for (var k = 0; k < 4; k++)
          StageItem('p$k', 'from the vertex stage, for this point'),
    ];

List<StageItem> stageOutputs(int slot) => switch (slot) {
      0 => const [
          StageItem('dx', 'displacement x, pixels'),
          StageItem('dy', 'displacement y, pixels')
        ],
      2 => const [
          StageItem('vx', 'point x, pixels'),
          StageItem('vy', 'point y, pixels'),
          StageItem('p0', 'parameter, read by the scan stage as in.p0'),
          StageItem('p1', 'parameter (in.p1)'),
          StageItem('p2', 'parameter (in.p2)'),
          StageItem('p3', 'parameter (in.p3)'),
        ],
      _ => const [],
    };
