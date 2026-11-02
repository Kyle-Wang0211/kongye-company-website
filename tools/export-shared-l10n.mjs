import {readFile,writeFile,mkdir} from 'node:fs/promises';
const source=new URL('../source/community_app/lib/l10n/',import.meta.url);
const output=new URL('../docs/i18n/',import.meta.url);
const catalogs={};
for(const language of ['zh','en']) {
 const arb=JSON.parse(await readFile(new URL(`app_${language}.arb`,source),'utf8'));
 catalogs[language]=Object.fromEntries(Object.entries(arb).filter(([key])=>!key.startsWith('@')));
}
const zh=Object.keys(catalogs.zh).sort(),en=Object.keys(catalogs.en).sort();
if(JSON.stringify(zh)!==JSON.stringify(en))throw Error('Chinese/English localization key mismatch');
for(const key of zh) {
 for(const language of ['zh','en'])if(typeof catalogs[language][key]!=='string'||!catalogs[language][key].trim())throw Error(`Empty localization: ${key}`);
 const placeholders=value=>[...value.matchAll(/\{([A-Za-z_]\w*)\s*[,}]/g)].map(match=>match[1]).sort();
 if(JSON.stringify(placeholders(catalogs.zh[key]))!==JSON.stringify(placeholders(catalogs.en[key])))throw Error(`Localization placeholder mismatch: ${key}`);
}
await mkdir(output,{recursive:true});
for(const language of ['zh','en'])await writeFile(new URL(`${language}.json`,output),JSON.stringify(catalogs[language],null,2)+'\n');
console.log(`Exported ${zh.length} paired localization keys`);
