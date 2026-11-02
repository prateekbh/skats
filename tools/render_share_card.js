// Renders web/launch/share_card.png (1200x630), the link-preview image used by the Open Graph and
// Twitter tags in web/shell.html. Uses Playwright's Chromium; run from the repo root:
//   node tools/render_share_card.js
const { chromium } = require('playwright');
const path = require('path');
(async () => {
	const browser = await chromium.launch();
	const page = await browser.newPage({ viewport: { width: 1200, height: 630 } });
	await page.goto('file://' + path.resolve(__dirname, 'share_card.html'));
	await page.waitForTimeout(600);
	await page.screenshot({ path: path.resolve(__dirname, '../web/launch/share_card.png') });
	await browser.close();
	console.log('wrote web/launch/share_card.png');
})();
