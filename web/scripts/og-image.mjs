// Saves the share card at /og (development only) to public/og-image.png.
//   npm run dev   # in another terminal
//   npm run og
import { chromium } from 'playwright-core'

const base = (process.env.BASE_URL || 'http://localhost:8186').replace(/\/$/, '')
const browser = await chromium.launch()
try {
  const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 })
  const response = await page.goto(`${base}/og`, { waitUntil: 'load' })
  if (!response?.ok()) throw new Error(`${base}/og answered ${response?.status()}; is \`npm run dev\` running?`)
  await page.evaluate(() => document.fonts.ready)
  // The dev server's floating Next.js badge isn't part of the card.
  await page.evaluate(() => document.querySelectorAll('nextjs-portal').forEach((element) => element.remove()))
  // Let the popover finish its entrance.
  await page.waitForTimeout(800)
  await page.screenshot({ path: 'public/og-image.png', clip: { x: 0, y: 0, width: 1200, height: 630 } })
  console.log('Saved public/og-image.png')
} finally {
  await browser.close()
}
