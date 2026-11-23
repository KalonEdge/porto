// One entry per scroll step of the landing page. `scene` is the room the laptop
// sits in while the section is on screen, `wallpaper` overrides the desktop
// picture when it differs, `menu` labels it in the laptop's menu bar, and `logo`
// is the brand colour that reads against that room's plain top centre.
export type Section = {
  id: string
  menu: string
  scene: string
  wallpaper?: string
  logo: 'dark' | 'light'
}

export const SECTIONS: readonly Section[] = [
  { id: 'servers', menu: 'Servers', scene: 'house', logo: 'dark' },
  { id: 'sessions', menu: 'Sessions', scene: 'coffee-shop', logo: 'light' },
  { id: 'leaks', menu: 'Leaks', scene: 'home-office', logo: 'light' },
  { id: 'clean-up', menu: 'Clean up', scene: 'coworking', logo: 'light' },
  { id: 'terminal', menu: 'Terminal', scene: 'tech-office', logo: 'light' },
  { id: 'translations', menu: 'Languages', scene: 'japanese-cafe', wallpaper: 'coffee-shop', logo: 'light' },
  { id: 'get-it', menu: 'Download', scene: 'corporate-office', logo: 'light' },
]

export const TERMINAL = 4
export const TRANSLATIONS = 5
export const GET_IT = SECTIONS.length - 1

/** A photo as a CSS background, preferring AVIF and WebP over the original JPEG. */
export const photo = (folder: 'scenes' | 'wallpapers', name: string) =>
  `image-set(url(/${folder}/${name}.avif) type("image/avif"), url(/${folder}/${name}.webp) type("image/webp"), url(/${folder}/${name}.jpg) type("image/jpeg"))`
