// Braille characters hold 2×4 dots each, so a row of text can draw a line chart.

const DOTS = [
  [0x01, 0x08],
  [0x02, 0x10],
  [0x04, 0x20],
  [0x40, 0x80],
]

export function brailleCanvas(columns: number, rows: number) {
  const bits = Array.from({ length: rows }, () => new Array<number>(columns).fill(0))
  const set = (x: number, y: number) => {
    if (x < 0 || y < 0 || x >= columns * 2 || y >= rows * 4) return
    bits[Math.floor(y / 4)][Math.floor(x / 2)] |= DOTS[y % 4][x % 2]
  }
  /** Joins the points into one unbroken line. */
  const plot = (points: [number, number][]) => {
    points.forEach(([x, y], index) => {
      set(x, y)
      const next = points[index + 1]
      if (!next) return
      const steps = Math.max(Math.abs(next[0] - x), Math.abs(next[1] - y))
      for (let step = 1; step <= steps; step++) {
        set(Math.round(x + ((next[0] - x) * step) / steps), Math.round(y + ((next[1] - y) * step) / steps))
      }
    })
  }
  const char = (row: number, column: number) => String.fromCharCode(0x2800 + bits[row][column])
  const empty = (row: number, column: number) => bits[row][column] === 0
  return { set, plot, char, empty }
}

/** The row sparkline: evenly spaced samples scaled to their own range, one row tall. */
export function sparkline(values: number[], columns = 8) {
  const low = Math.min(...values)
  const high = Math.max(...values)
  const range = Math.max(high - low, Math.abs(high) * 0.05, 1)
  const width = columns * 2 - 1
  const byColumn = new Map<number, number>()
  values.forEach((value, index) => byColumn.set(Math.round((index / (values.length - 1)) * width), value))
  const grid = brailleCanvas(columns, 1)
  grid.plot(
    [...byColumn.entries()]
      .sort((a, b) => a[0] - b[0])
      .map(([x, value]): [number, number] => [x, Math.round(((1 - (value - low) / range) * 0.8 + 0.1) * 3)]),
  )
  return Array.from({ length: columns }, (_, column) => grid.char(0, column)).join('')
}
