import type { Metadata } from 'next'
import { notFound } from 'next/navigation'
import { OgCard } from './OgCard'

// The 1200 × 630 share card, built from the real popover so it never drifts
// from the product. Development only: `npm run og` saves it to public/og-image.png.

export const metadata: Metadata = { robots: { index: false, follow: false } }

export default function Page() {
  if (process.env.NODE_ENV === 'production') notFound()
  return <OgCard />
}
