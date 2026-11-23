import strings from './strings.json'

// Keep these codes aligned with InterfaceLanguage in the app's Localization.swift.
export const LANGUAGES = [
  { code: 'en', label: 'English', name: 'English' },
  { code: 'de', label: 'Deutsch', name: 'German' },
  { code: 'fr', label: 'Français', name: 'French' },
  { code: 'es', label: 'Español', name: 'Spanish' },
  { code: 'zh-Hans', label: '简体中文', name: 'Simplified Chinese' },
  { code: 'he', label: 'עברית', name: 'Hebrew' },
  { code: 'ja', label: '日本語', name: 'Japanese' },
  { code: 'uk', label: 'Українська', name: 'Ukrainian' },
] as const

export type LanguageCode = (typeof LANGUAGES)[number]['code']
export type AppLanguage = 'system' | LanguageCode

export const languageLabel = (code: AppLanguage) =>
  LANGUAGES.find((language) => language.code === code)?.label ?? 'System default'

const tables = strings as Record<string, Record<string, string>>

// printf-style %@ and %d, including explicit positions like %2$@.
const fill = (template: string, args: unknown[]) => {
  let next = 0
  return template.replace(/%(?:(\d+)\$)?([@d%])/g, (_, position: string | undefined, kind: string) =>
    kind === '%' ? '%' : String(args[position ? Number(position) - 1 : next++]),
  )
}

export type Translator = ReturnType<typeof translator>

/** The app's L10n for the demo: English keys, per-language tables, the same plural rules. */
export function translator(code: AppLanguage) {
  const table = code === 'en' || code === 'system' ? undefined : tables[code]
  const text = (key: string) => table?.[key] ?? key
  const format = (key: string, ...args: unknown[]) => fill(text(key), args)
  return {
    code,
    rtl: code === 'he',
    text,
    format,
    /** Ukrainian has one/few/many noun forms; French treats zero as singular. */
    counted(singular: string, plural: string, count: number) {
      if (code === 'uk') {
        const last = count % 10
        const lastTwo = count % 100
        if (last === 1 && lastTwo !== 11) return text(singular)
        if (last >= 2 && last <= 4 && !(lastTwo >= 12 && lastTwo <= 14)) return text(`${plural} (few)`)
      }
      return text(count === 1 || (code === 'fr' && count === 0) ? singular : plural)
    },
    /** A span in minutes, like the app: "<1m", "12m", "3h 12m", "2d". */
    duration(minutes: number, short = false) {
      if (minutes < 1) return short ? format('%dm', 1) : text('<1m')
      if (minutes < 60) return format('%dm', minutes)
      const hours = Math.floor(minutes / 60)
      if (hours >= 24) return format('%dd', Math.floor(hours / 24))
      const rest = minutes % 60
      return short || rest === 0 ? format('%dh', hours) : format('%dh %dm', hours, rest)
    },
  }
}
