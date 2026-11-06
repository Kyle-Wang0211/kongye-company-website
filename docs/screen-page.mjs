import {initSiteLocale,t,localeEvent} from './site-l10n.mjs?v=account-library-20261106-v44';
const keys=['siteScreenOne','siteScreenTwo','siteScreenThree'];
const requested=Number(new URL(location.href).searchParams.get('screen'));
const index=Number.isInteger(requested)&&requested>=1&&requested<=3?requested-1:0;
document.querySelector('#screen-title').dataset.i18n=keys[index];
await initSiteLocale();
function title(){document.title=(index===0?'瓷影｜器物与日常':index===1?'云栖山庄 · 三维度假导览':t(keys[index]))+' · '+t('siteBrand');}
window.addEventListener(localeEvent,title);title();

if(index===0){const {mountCeramicEvent}=await import('./ceramic-event.mjs?v=account-library-20261106-v44');mountCeramicEvent();}

if(index===1){const [{mountCommunityResort},{resortConfig}]=await Promise.all([import('./community-resort.mjs?v=monochrome-20261106-v46'),import('./community-resort-data.mjs?v=resort-guide-20261106-v45')]);mountCommunityResort(resortConfig);}
