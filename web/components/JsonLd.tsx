/**
 * Structured data for search engines and agents. React writes a script's text
 * child as-is, and escaping `<` means the JSON can never close the tag early.
 */
export function JsonLd({ data }: { data: object }) {
  return <script type="application/ld+json">{JSON.stringify(data).replace(/</g, '\\u003c')}</script>
}
