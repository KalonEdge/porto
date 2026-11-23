import { JsonLd } from '@/components/JsonLd'
import { Landing } from '@/components/landing/Landing'
import { softwareApplication, website } from '@/lib/structured-data'

export default function Home() {
  return (
    <>
      {/* The first room and the laptop are what paint first, so fetch them with the HTML. */}
      <link rel="preload" as="image" href="/scenes/house.avif" type="image/avif" fetchPriority="high" media="(min-width: 900px) and (min-aspect-ratio: 1/1)" />
      <link rel="preload" as="image" href="/scenes/laptop.avif" type="image/avif" media="(min-width: 900px) and (min-aspect-ratio: 1/1)" />
      <JsonLd data={[softwareApplication(), website()]} />
      <Landing />
    </>
  )
}
