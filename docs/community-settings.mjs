import {currentLocale, setLocale, t, localeEvent} from './site-l10n.mjs?v=shared-community-20261106-v40';

const accountMenu = document.querySelector('#account-menu');
const dialog = document.querySelector('#site-settings');
const sidebarOpener = document.querySelector('#open-sidebar-settings');
const accountOpener = document.querySelector('#open-settings');
const openers = [sidebarOpener, accountOpener].filter(Boolean);
const closeButton = document.querySelector('#close-settings');
let activeOpener;
let returnFocus;
let closeTimer;
let languageTimer;

function button(id, key) {
  const element = document.createElement('button');
  element.id = id;
  element.type = 'button';
  element.dataset.i18n = key;
  element.textContent = t(key);
  element.setAttribute('role', 'menuitem');
  return element;
}

const settingsMenu = document.createElement('div');
settingsMenu.id = 'site-settings-menu';
settingsMenu.className = 'site-settings-popover';
settingsMenu.hidden = true;
settingsMenu.setAttribute('role', 'menu');
settingsMenu.setAttribute('aria-label', t('siteSettings'));
const languageButton = button('settings-language', 'webSettingsLanguage');
languageButton.setAttribute('aria-haspopup', 'menu');
languageButton.setAttribute('aria-expanded', 'false');
languageButton.setAttribute('aria-controls', 'site-language-menu');
const helpButton = button('settings-help', 'webSettingsHelp');
settingsMenu.append(languageButton, helpButton);

const languageMenu = document.createElement('div');
languageMenu.id = 'site-language-menu';
languageMenu.className = 'site-settings-popover site-language-popover';
languageMenu.hidden = true;
languageMenu.setAttribute('role', 'menu');
languageMenu.setAttribute('aria-labelledby', languageButton.id);
const languageOptions = ['zh', 'en'].map(locale => {
  const option = button(`settings-locale-${locale}`, '');
  delete option.dataset.i18n;
  option.textContent = locale === 'zh' ? '中文' : 'English';
  option.lang = locale === 'zh' ? 'zh-CN' : 'en';
  option.dataset.locale = locale;
  option.setAttribute('role', 'menuitemradio');
  option.addEventListener('click', () => {
    setLocale(locale);
    closeMenu(true);
  });
  languageMenu.append(option);
  return option;
});
document.body.append(settingsMenu, languageMenu);

// Keep the original company/support markup in the page. Help uses its existing dialog.
for (const section of dialog.querySelectorAll(':scope > section, :scope > footer')) section.hidden = true;
const oldToggle = document.querySelector('#site-locale-toggle');
if (oldToggle) oldToggle.hidden = true;
const title = document.querySelector('#settings-title');
title.dataset.i18n = 'webHelpTitle';
title.textContent = t('webHelpTitle');
const helpContent = document.createElement('div');
helpContent.className = 'settings-help-content';
for (const topic of ['View', 'Publish', 'Account']) {
  const faq = document.createElement('details');
  const question = document.createElement('summary');
  question.dataset.i18n = `webHelp${topic}Question`;
  question.textContent = t(question.dataset.i18n);
  const answer = document.createElement('p');
  answer.dataset.i18n = `webHelp${topic}Answer`;
  answer.textContent = t(answer.dataset.i18n);
  faq.append(question, answer);
  helpContent.append(faq);
}
const contact = document.createElement('p');
contact.className = 'settings-help-contact';
const contactLabel = document.createElement('span');
contactLabel.dataset.i18n = 'webHelpContactLabel';
contactLabel.textContent = t('webHelpContactLabel');
const email = document.createElement('a');
email.href = 'mailto:kaidong@kongye.space';
email.textContent = 'kaidong@kongye.space';
contact.append(contactLabel, document.createTextNode(' '), email);
helpContent.append(contact);
dialog.append(helpContent);

function place(panel, anchor, preferRight = true) {
  const bounds = anchor.getBoundingClientRect();
  const gap = 4;
  const margin = 8;
  const width = panel.offsetWidth;
  const height = panel.offsetHeight;
  const right = bounds.right + gap;
  const left = bounds.left - width - gap;
  let x = preferRight ? right : bounds.right - width;
  if (preferRight && x + width > window.innerWidth - margin) x = left;
  x = Math.max(margin, Math.min(x, window.innerWidth - width - margin));
  const y = Math.max(margin, Math.min(bounds.top, window.innerHeight - height - margin));
  panel.style.left = `${x}px`;
  panel.style.top = `${y}px`;
}

function cancelClose() {
  clearTimeout(closeTimer);
  clearTimeout(languageTimer);
}
function closeLanguage() {
  languageMenu.hidden = true;
  languageButton.setAttribute('aria-expanded', 'false');
}
function closeMenu(restoreFocus = false) {
  cancelClose();
  closeLanguage();
  settingsMenu.hidden = true;
  for (const opener of openers) opener.setAttribute('aria-expanded', 'false');
  if (restoreFocus) returnFocus?.focus();
}
function updateLanguage() {
  for (const option of languageOptions) option.setAttribute('aria-checked', String(option.dataset.locale === currentLocale()));
  settingsMenu.setAttribute('aria-label', t('siteSettings'));
}
function openMenu(opener, focus = false) {
  cancelClose();
  activeOpener = opener;
  returnFocus = opener === accountOpener ? document.querySelector('#account-summary') : opener;
  if (accountMenu) accountMenu.open = false;
  for (const item of openers) item.setAttribute('aria-expanded', String(item === opener));
  settingsMenu.hidden = false;
  updateLanguage();
  place(settingsMenu, returnFocus, opener === sidebarOpener);
  if (focus) languageButton.focus();
}
function placeLanguage() {
  const bounds = languageButton.getBoundingClientRect();
  const width = languageMenu.offsetWidth;
  // When neither side has room, shift the parent so both menus remain usable.
  if (bounds.right + width + 4 > window.innerWidth - 8 && bounds.left - width - 4 < 8) {
    settingsMenu.style.left = '8px';
  }
  place(languageMenu, languageButton);
}
function openLanguage(focus = false) {
  cancelClose();
  languageMenu.hidden = false;
  languageButton.setAttribute('aria-expanded', 'true');
  placeLanguage();
  if (focus) languageOptions.find(option => option.dataset.locale === currentLocale()).focus();
}
function scheduleClose() {
  cancelClose();
  closeTimer = setTimeout(() => {
    if (!settingsMenu.contains(document.activeElement) && !languageMenu.contains(document.activeElement)) closeMenu();
  }, 220);
}

for (const opener of openers) {
  opener.setAttribute('aria-haspopup', 'menu');
  opener.setAttribute('aria-controls', settingsMenu.id);
  opener.setAttribute('aria-expanded', 'false');
  opener.addEventListener('click', () => openMenu(opener, true));
  opener.addEventListener('keydown', event => {
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      openMenu(opener, true);
    }
  });
}
sidebarOpener?.addEventListener('pointerenter', event => {
  if (event.pointerType !== 'touch') openMenu(sidebarOpener);
});
sidebarOpener?.addEventListener('pointerleave', scheduleClose);
for (const panel of [settingsMenu, languageMenu]) {
  panel.addEventListener('pointerenter', cancelClose);
  panel.addEventListener('pointerleave', scheduleClose);
  panel.addEventListener('focusin', cancelClose);
  panel.addEventListener('focusout', () => setTimeout(() => {
    if (!settingsMenu.contains(document.activeElement) && !languageMenu.contains(document.activeElement) && !openers.includes(document.activeElement)) closeMenu();
  }, 0));
  panel.addEventListener('keydown', event => {
    const items = panel === settingsMenu ? [languageButton, helpButton] : languageOptions;
    const index = items.indexOf(document.activeElement);
    if (['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) {
      event.preventDefault();
      const next = event.key === 'Home' ? 0 : event.key === 'End' ? items.length - 1 : (index + (event.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length;
      items[next].focus();
    }
    if (panel === languageMenu && event.key === 'ArrowLeft') {
      event.preventDefault();
      closeLanguage();
      languageButton.focus();
    }
  });
}
languageButton.addEventListener('pointerenter', event => { if (event.pointerType !== 'touch') openLanguage(); });
languageButton.addEventListener('click', () => openLanguage(true));
languageButton.addEventListener('keydown', event => {
  if (event.key === 'ArrowRight') {
    event.preventDefault();
    openLanguage(true);
  }
});
helpButton.addEventListener('pointerenter', () => {
  languageTimer = setTimeout(closeLanguage, 180);
});
helpButton.addEventListener('focus', closeLanguage);
helpButton.addEventListener('click', () => {
  closeMenu();
  dialog.showModal();
});
closeButton.addEventListener('click', () => dialog.close());
dialog.addEventListener('close', () => returnFocus?.focus());
document.addEventListener('click', event => {
  if (!accountMenu?.contains(event.target) && accountMenu) accountMenu.open = false;
  if (![settingsMenu, languageMenu, ...openers].some(element => element.contains(event.target))) closeMenu();
});
document.addEventListener('keydown', event => {
  if (event.key === 'Escape') {
    if (accountMenu) accountMenu.open = false;
    if (!settingsMenu.hidden) {
      event.preventDefault();
      closeMenu(true);
    }
  }
});
window.addEventListener(localeEvent, updateLanguage);
window.addEventListener('resize', () => {
  if (!settingsMenu.hidden) place(settingsMenu, returnFocus, activeOpener === sidebarOpener);
  if (!languageMenu.hidden) placeLanguage();
});
window.addEventListener('scroll', event => {
  if (!settingsMenu.contains(event.target) && !languageMenu.contains(event.target)) closeMenu();
}, {capture: true, passive: true});
