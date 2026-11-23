import { type NextRequest, NextResponse } from 'next/server'

// Anonymous usage from the Mac app (see app/Sources/Porto/Engine/Usage.swift).
// Copies that share usage request /usage/<feature> once a day for each feature
// they used, so request counts per path are installs per feature. Nothing is
// stored or forwarded here; the response is empty. Keep in step with Usage.Feature.
const FEATURES = new Set([
  'active',
  'popover',
  'shortcut',
  'details',
  'open-browser',
  'open-editor',
  'stop',
  'restart',
  'clean-up',
  'auto-clean-up',
  'memory-alert',
  'resume-session',
  'vercel-preview',
  'pull-request',
])

// Agents can read any page as Markdown (app/md): add .md to its URL, or ask for
// text/markdown ahead of HTML in the Accept header.
function prefersMarkdown(accept: string) {
  const markdown = accept.indexOf('text/markdown')
  const html = accept.indexOf('text/html')
  return markdown >= 0 && (html < 0 || markdown < html)
}

function markdownPath(pathname: string, accept: string) {
  if (pathname.endsWith('.md')) return `/md${pathname === '/index.md' ? '/index' : pathname.slice(0, -3)}`
  if (prefersMarkdown(accept)) return `/md${pathname === '/' ? '/index' : pathname.replace(/\/$/, '')}`
  return null
}

export function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl
  if (pathname.startsWith('/usage/')) {
    const feature = pathname.slice('/usage/'.length)
    return new NextResponse(null, { status: FEATURES.has(feature) ? 204 : 404, headers: { 'cache-control': 'no-store' } })
  }

  // The proxy runs before the cache, so HTML and Markdown can share a URL.
  const markdown = markdownPath(pathname, request.headers.get('accept') ?? '')
  return markdown ? NextResponse.rewrite(new URL(markdown, request.url)) : NextResponse.next()
}

export const config = { matcher: ['/usage/:path*', '/', '/index.md', '/guides', '/guides.md', '/guides/:path*'] }
