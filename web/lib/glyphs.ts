// 5×5 dot-matrix glyphs, the same ones the Mac app draws in its menu bar icon
// and onboarding. '#' is lit, 'a' lit amber, '.' off.
export const GLYPHS = {
  /** Porto's mark: a porthole, a ring of dots around a lit centre. */
  porthole: ['.###.', '#...#', '#.#.#', '#...#', '.###.'],
  P: ['####.', '#...#', '####.', '#....', '#....'],
  O: ['.###.', '#...#', '#...#', '#...#', '.###.'],
  R: ['####.', '#...#', '####.', '#..#.', '#...#'],
  T: ['#####', '..#..', '..#..', '..#..', '..#..'],
  question: ['.###.', '#...#', '..##.', '.....', '..#..'],
  bang: ['..a..', '..a..', '..a..', '.....', '..a..'],
  questionBang: ['##..a', '..#.a', '.#..a', '.....', '.#..a'],
  line: ['....#', '...#.', '.#...', '#.#..', '.....'],
  bars: ['....#', '...##', '.#.##', '.####', '#####'],
  count: ['#####', '#....', '####.', '....#', '####.'],
  leak: ['....a', '...a.', '..#..', '.#...', '#....'],
  /** The porthole turned amber: a server needs attention. */
  alert: ['.aaa.', 'a...a', 'a.a.a', 'a...a', '.aaa.'],
} as const

export type Glyph = keyof typeof GLYPHS

export const isLit = (glyph: Glyph, row: number, column: number) => GLYPHS[glyph][row][column] !== '.'
