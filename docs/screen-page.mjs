import {initSiteLocale,t,localeEvent} from './site-l10n.mjs?v=three-screens-20261104-v21';
const keys=['siteScreenOne','siteScreenTwo','siteScreenThree'];
const requested=Number(new URL(location.href).searchParams.get('screen'));
const index=Number.isInteger(requested)&&requested>=1&&requested<=3?requested-1:0;
document.querySelector('#screen-title').dataset.i18n=keys[index];
await initSiteLocale();
function title(){document.title=t(keys[index])+' · '+t('siteBrand');}
window.addEventListener(localeEvent,title);title();
