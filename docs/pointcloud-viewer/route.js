// These three immutable derivatives have source-local XYZ and no CRS WKT.
// Keep their existing renderer until their coordinate metadata is available.
const legacyNames = [
  "streaming-ee0ea729a8f9e302cb38003addaffca0c1beecb0cd8453bef144a3667bb4add2.copc.laz",
  "streaming-183f60bfacc9cad581d7e0344b812ac6566780b9656dc1ddf1decfbdbc5ae150.copc.laz",
  "streaming-9a14584c6eae41b11800de4964561ed51d70f1c17fef43de58e3a6dbd0b956fc.copc.laz"
];
const source = new URLSearchParams(location.search).get('source');
const sourceUrl = source ? new URL(source, location.href) : null;
const legacy = sourceUrl?.origin === 'https://api.kongye.space'
  && legacyNames.includes(sourceUrl.pathname.split('/').pop());
const target = new URL(legacy ? './legacy.html' : './copc/index.html', location.href);
target.search = location.search;
if (sourceUrl) target.searchParams.set('source', sourceUrl.href);
target.hash = location.hash;
location.replace(target.href);
