const fs = require('fs');
const path = require('path');
const https = require('https');

const OUT = process.env.out;
const UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ' +
  'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/104.0.0.0 Safari/537.36';

const cssUrls = [
  'https://fonts.googleapis.com/css2?family=Geist:wght@100..900&display=swap',
  'https://fonts.googleapis.com/css2?family=Geist+Mono:wght@100..900&display=swap',
  'https://fonts.googleapis.com/css2?family=Press+Start+2P:wght@400&display=swap',
];

function get(url, asBuffer) {
  return new Promise((resolve, reject) => {
    https
      .get(url, { headers: { 'User-Agent': UA } }, (res) => {
        if (res.statusCode !== 200) {
          reject(new Error(res.statusCode + ' ' + url));
          return;
        }
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () =>
          resolve(asBuffer ? Buffer.concat(chunks) : Buffer.concat(chunks).toString('utf8'))
        );
      })
      .on('error', reject);
  });
}

async function main() {
  const fontsDir = path.join(OUT, 'fonts');
  fs.mkdirSync(fontsDir, { recursive: true });
  const mock = {};
  let idx = 0;
  for (const url of cssUrls) {
    const css = await get(url, false);
    const rewritten = [];
    for (const line of css.split('\n')) {
      const match = /src: url\((.+?)\)/.exec(line);
      if (match) {
        const fontUrl = match[1];
        const ext = (/\.(woff2|woff|ttf|otf|eot)(\?|$)/.exec(fontUrl) || [, 'woff2'])[1];
        const buffer = await get(fontUrl, true);
        const name = 'font_' + idx++ + '.' + ext;
        fs.writeFileSync(path.join(fontsDir, name), buffer);
        rewritten.push(line.replace(fontUrl, '@FONTS_DIR@/' + name));
      } else {
        rewritten.push(line);
      }
    }
    mock[url] = rewritten.join('\n');
  }
  fs.writeFileSync(path.join(OUT, 'mock.json'), JSON.stringify(mock));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
