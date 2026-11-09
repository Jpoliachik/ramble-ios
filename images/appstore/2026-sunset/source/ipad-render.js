// Renders iPad (2064x2752) versions of the five sunset frames from one-line.html.
// For each frame: hide the other frames' copy and devices, screenshot the whole
// panorama, extend its outer edges, crop a 0.75-aspect window centred on the frame.
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const path = require('path');

const SRC = process.argv[2];
const OUT = process.argv[3];

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 6450, height: 2796 }, deviceScaleFactor: 1 });
  await page.goto('file://' + SRC + '?bg=t&ipad=1');
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(1500);
  for (let i = 0; i < 5; i++) {
    await page.evaluate((i) => {
      const lo = i * 1290 + 645 - 1048, hi = i * 1290 + 645 + 1048;
      for (const el of document.querySelectorAll('#pano > *')) {
        if (['bg', 'flair', 'line'].includes(el.id) || el.classList.contains('seam')) continue;
        let left;
        if (el.classList.contains('zoomwrap')) left = 3870;
        else if (el.style.left) left = parseFloat(el.style.left);
        else { el.style.visibility = 'visible'; const r = el.getBoundingClientRect(); left = r.left + r.width / 2; }
        el.style.visibility = Math.floor(left / 1290) === i ? 'visible' : 'hidden';
      }
      // let the line's words run past the old frame seams, but drop any cut by the crop
      for (const el of document.querySelectorAll('#line [clip-path], #flair [clip-path]')) {
        if (el.closest('#words') || el.closest('#ink')) el.removeAttribute('clip-path');
      }
      for (const t of document.querySelectorAll('#words text, #words textPath')) {
        const txt = t.tagName === 'textPath' ? t.parentNode : t;
        txt.style.visibility = 'visible';
        const r = txt.getBoundingClientRect();
        txt.style.visibility = (r.left >= lo && r.right <= hi) ? 'visible' : 'hidden';
      }
    }, i);
    await page.waitForTimeout(300);
    await page.screenshot({ path: path.join(OUT, `pano-${i + 1}.png`) });
  }
  await browser.close();
})();
