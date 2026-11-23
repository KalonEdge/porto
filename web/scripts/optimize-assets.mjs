// Encodes AVIF and WebP copies of the scene photography next to each JPEG.
// The landing page asks for them through image-set(), so browsers download the
// smallest format they support and fall back to the original JPEG.
// Run with `npm run assets` after adding or replacing a photo.
import { readdir, stat } from 'node:fs/promises'
import path from 'node:path'
import sharp from 'sharp'

const FOLDERS = ['public/scenes', 'public/wallpapers']
const FORMATS = [
  ['avif', (image) => image.avif({ quality: 62, effort: 7, chromaSubsampling: '4:4:4' })],
  ['webp', (image) => image.webp({ quality: 86, effort: 6, smartSubsample: true })],
]

const kb = (bytes) => `${Math.round(bytes / 1024)} KB`
let before = 0
let after = 0

for (const folder of FOLDERS) {
  for (const name of (await readdir(folder)).filter((file) => file.endsWith('.jpg'))) {
    const source = path.join(folder, name)
    const original = (await stat(source)).size
    const sizes = []
    for (const [extension, encode] of FORMATS) {
      const target = source.replace(/\.jpg$/, `.${extension}`)
      await encode(sharp(source)).toFile(target)
      sizes.push([extension, (await stat(target)).size])
    }
    before += original
    after += Math.min(...sizes.map(([, size]) => size))
    console.log(`${source.padEnd(38)} jpg ${kb(original).padStart(7)}  ${sizes.map(([ext, size]) => `${ext} ${kb(size).padStart(7)}`).join('  ')}`)
  }
}

console.log(`\nSmallest formats total ${kb(after)} instead of ${kb(before)} (${Math.round((1 - after / before) * 100)}% less).`)
