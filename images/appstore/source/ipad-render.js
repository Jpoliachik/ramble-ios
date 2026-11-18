// Renders the one iPad App Store screenshot (2064x2752): Home on an iPad,
// centred on the sunset background, no headline or line.
// Usage: node ipad-render.js <abs path to one-line.html> <out png>
const { chromium } = require('playwright');

const SRC = process.argv[2];
const OUT = process.argv[3];
const W = 2097, H = 2796, CX = 3225;   // a 3:4 window centred on frame 3, where the background is widest
const DSF = 2064 / W;                   // 2097 x 2796 → 2064 x 2752

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 6450, height: 2796 }, deviceScaleFactor: DSF });
  await page.goto('file://' + SRC + '?bg=t&ipad=1');
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(1500);
  await page.evaluate((cx) => {
    const home = [...document.querySelectorAll('.dev > .phone')].pop().parentElement;   // the Home list iPad
    for (const el of document.querySelectorAll('#pano > *')) {
      if (el.id !== 'bg') el.style.visibility = 'hidden';
    }
    document.getElementById('pano').appendChild(home);
    home.style.visibility = 'visible';
    home.style.left = cx + 'px'; home.style.top = '1440px'; home.style.setProperty('--s', 2.5);
  }, CX);
  await page.waitForTimeout(300);
  await page.screenshot({ path: OUT, clip: { x: CX - W / 2, y: 0, width: W, height: H } });
  await browser.close();
})();
