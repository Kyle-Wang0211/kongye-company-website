// Catalogs are exported from the application's authoritative AppL10n ARBs.
export const localeStorageKey = 'flutter.pw.locale.override.v1';
export const localeEvent = 'pw:localechange';
export function readLocale(storage, language = 'zh') {
  try {
    const raw = storage?.getItem(localeStorageKey);
    const value = raw == null ? null : JSON.parse(raw);
    if (value === 'zh' || value === 'en') return value;
  } catch { /* Storage may be unavailable or contain a damaged preference. */ }
  return /^zh(?:-|$)/i.test(language) ? 'zh' : 'en';
}
export function persistLocale(storage, value) {
  if (!['zh', 'en'].includes(value)) throw new TypeError('Invalid locale');
  try { storage?.setItem(localeStorageKey, JSON.stringify(value)); } catch { /* Session choice remains usable. */ }
}
const releaseVersion = 'publication-framing-20261106-v38';
let catalogs = {};
async function loadCatalogs() {
  const entries = await Promise.all(['zh', 'en'].map(async locale => {
    const url = new URL(`./i18n/${locale}.json`, import.meta.url);
    url.searchParams.set('v', releaseVersion);
    const catalog = typeof window === 'undefined'
      ? JSON.parse(await (await import('node:fs/promises')).readFile(url, 'utf8'))
      : await fetch(url, {signal: AbortSignal.timeout(15000)}).then(response => { if (!response.ok) throw Error('Catalog unavailable'); return response.json(); });
    return [locale, catalog];
  }));
  const result = Object.fromEntries(entries);
  for (const [locale, catalog] of entries) {
    for (const key of Object.keys(result.zh)) {
      if (typeof catalog[key] !== 'string') throw Error(`Missing ${locale} translation: ${key}`);
    }
  }
  catalogs = result;
}
export const localeReady = loadCatalogs();
await localeReady;
let locale = 'zh';
function browserStorage() { if (typeof window === 'undefined') return undefined; try { return globalThis.localStorage; } catch { return undefined; } }
if (typeof window !== 'undefined') locale = readLocale(browserStorage(), globalThis.navigator?.language || 'en');
export function currentLocale() { return locale; }
export function t(key, values = {}) {
  const template = catalogs[locale]?.[key];
  if (typeof template !== 'string') return key;
  return template.replace(/\{(\w+)\}/g, (match, name) => values[name] == null ? match : String(values[name]));
}
export function localizeElement(element, key, values = {}, attribute) {
  element.dataset[attribute === 'aria-label' ? 'i18nAria' : 'i18n'] = key;
  if (Object.keys(values).length) element.dataset.i18nValues = JSON.stringify(values);
  const text = t(key, values);
  if (attribute) element.setAttribute(attribute, text); else element.textContent = text;
  return element;
}
export function applyLocale(document) {
  document.documentElement.lang = locale === 'zh' ? 'zh-CN' : 'en';
  for (const [selector, field, attribute] of [
    ['[data-i18n]', 'i18n', null],
    ['[data-i18n-aria]', 'i18nAria', 'aria-label'],
    ['[data-i18n-content]', 'i18nContent', 'content'],
  ]) for (const element of document.querySelectorAll(selector)) {
    const text = t(element.dataset[field], JSON.parse(element.dataset.i18nValues || '{}'));
    if (attribute) element.setAttribute(attribute, text); else element.textContent = text;
  }
  const button = document.getElementById('site-locale-toggle');
  if (button) { button.textContent = locale === 'zh' ? '中 / EN' : 'EN / 中'; button.setAttribute('aria-pressed', String(locale === 'en')); }
}
export function setLocale(value) {
  if (!['zh', 'en'].includes(value)) throw new TypeError('Invalid locale');
  locale = value;
  persistLocale(browserStorage(), locale);
  if (typeof document !== 'undefined') applyLocale(document);
  if (typeof window !== 'undefined') window.dispatchEvent(new CustomEvent(localeEvent, { detail: { locale } }));
}
export async function initSiteLocale() {
  await localeReady;
  persistLocale(browserStorage(), locale);
  applyLocale(document);
  document.getElementById('site-locale-toggle')?.addEventListener('click', () => setLocale(locale === 'zh' ? 'en' : 'zh'));
  // Same-origin community navigation reads this exact shared_preferences value.
  document.addEventListener('click', event => {
    const link = event.target.closest?.('a[href]');
    if (link && new URL(link.href, location.href).pathname.startsWith('/community/')) persistLocale(browserStorage(), locale);
  }, { capture: true });
  const restore = () => { const next = readLocale(browserStorage(), navigator.language); if (next !== locale) setLocale(next); };
  window.addEventListener('storage', event => { if (event.key === localeStorageKey || event.key === null) restore(); });
  window.addEventListener('pageshow', restore);
}
