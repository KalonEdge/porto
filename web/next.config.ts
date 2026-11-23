import fs from 'node:fs'
import path from 'node:path'
import type { NextConfig } from 'next'

// The Mac app's version, for the site's structured data. Anywhere the app
// source isn't checked out beside the site, the version is left out.
let appVersion = ''
try {
  const plist = fs.readFileSync(path.join(import.meta.dirname, '../app/Info.plist'), 'utf8')
  appVersion = plist.match(/<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/)?.[1] ?? ''
} catch {}

// The app's tip jar opens /tip, so the payment page can change without an app
// update. Set TIP_URL to your payment link; without it /tip isn't offered.
const tip = process.env.TIP_URL?.trim()

// Without a local build of the download (public/Porto.dmg), point it at a hosted release.
const release = process.env.PORTO_DOWNLOAD_URL?.trim()
const hasDownload = fs.existsSync(path.join(import.meta.dirname, 'public/Porto.dmg'))

const nextConfig: NextConfig = {
  poweredByHeader: false,
  // This folder is the project root, even with a lockfile further up the disk.
  turbopack: { root: import.meta.dirname },
  env: { APP_VERSION: appVersion },
  async redirects() {
    const redirects = []
    if (tip) redirects.push({ source: '/tip', destination: tip, permanent: false })
    if (release && !hasDownload) redirects.push({ source: '/Porto.dmg', destination: release, permanent: false })
    return redirects
  },
  async headers() {
    // Fonts and photos only change with a deploy; let browsers keep them a week.
    const cached = { key: 'Cache-Control', value: 'public, max-age=604800, stale-while-revalidate=86400' }
    return [
      ...['/fonts/:file*', '/scenes/:file*', '/wallpapers/:file*'].map((source) => ({ source, headers: [cached] })),
      { source: '/Porto.dmg', headers: [{ key: 'Content-Type', value: 'application/x-apple-diskimage' }] },
    ]
  },
}

export default nextConfig
