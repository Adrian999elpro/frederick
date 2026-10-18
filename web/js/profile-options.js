export const ACCENTS = {red: "Rojo Frederick", blue: "Azul", green: "Verde", purple: "Violeta", gold: "Dorado"};
export const BADGES = {school: "🎓 Aprender", science: "🔬 Ciencia", music: "🎵 Música", sports: "⚽ Deporte", code: "💻 Tecnología", art: "🎨 Arte"};
export function normalizeCustomization(value = {}) {
  return { nickname: value.nickname || "", headline: value.headline || "", bio: value.bio || "", accent: Object.hasOwn(ACCENTS, value.accent) ? value.accent : "red", badge: Object.hasOwn(BADGES, value.badge) ? value.badge : "school", visibility: value.visibility === "public" ? "public" : "private", show_grades: value.show_grades === true };
}
