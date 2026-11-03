// Screenshots the HTML launcher (web/shell.html) on a device profile without the game engine:
//   node tools/launcher_shot.js out.png [device] [landscape|portrait]   (default: Pixel 7 landscape)
// Used to check the title page on phones. The game's own part is replaced by a stub that shows the menu.
const { chromium, devices } = require('playwright');
const fs = require('fs');
const path = require('path');
(async () => {
	const out = process.argv[2] || 'launcher.png';
	const name = process.argv[3] || 'Pixel 7';
	const landscape = (process.argv[4] || 'landscape') === 'landscape';
	const d = devices[landscape ? name + ' landscape' : name] || devices[name];
	const b = await chromium.launch();
	const ctx = await b.newContext({ ...d });
	const p = await ctx.newPage();
	const html = fs.readFileSync(path.resolve(__dirname, '../web/shell.html'), 'utf8')
		.replace('$GODOT_PROJECT_NAME', 'x').replace('$GODOT_HEAD_INCLUDE', '').replace('$GODOT_CONFIG', '{}').replace(/\$GODOT_[A-Z_]+/g, '""');
	const dir = path.resolve(__dirname, '../web');
	await p.route('**/*', (r) => {
		const u = new URL(r.request().url());
		if (u.hostname === 'shell.local' && u.pathname.startsWith('/__fonts/')) {
			return r.fulfill({ path: path.resolve(__dirname, '../assets/fonts', path.basename(u.pathname)) });
		}
		if (u.hostname === 'shell.local') {
			const f = path.join(dir, decodeURIComponent(u.pathname));
			if (u.pathname === '/' || u.pathname === '/index.html') return r.fulfill({ contentType: 'text/html', body: html });
			if (fs.existsSync(f)) return r.fulfill({ path: f });
			return r.fulfill({ status: 404, body: '' });
		}
		return r.abort();
	});
	await p.addInitScript(() => { window.Engine = function () { this.startGame = () => new Promise(() => {}); this.init = () => new Promise(() => {}); }; window.Engine.isWebGLAvailable = () => true; window.Engine.getMissingFeatures = () => []; });
	p.on('pageerror', (e) => console.log('pageerror', e.message));
	await p.goto('http://shell.local/');
	await p.addStyleTag({ content: "@font-face{font-family:Bangers;src:url('/__fonts/Bangers-Regular.ttf')}@font-face{font-family:'Comic Neue';font-weight:700;src:url('/__fonts/ComicNeue-Bold.ttf')}" });
	await p.waitForTimeout(400);
	const state = { episodes: [
		{ id: 'ep01', number: 'Episode 1', title: 'Dark Skies Over Megakat', villain: 'Dark Kat', story: 's', objectives: [], playable: true, best: 12000 },
		{ id: 'ep02', number: 'Episode 2', title: 'Turmoil Rising', villain: 'Turmoil', story: 's', objectives: [], playable: false, best: 0 },
		{ id: 'free', number: 'Free Flight', title: 'Endless Defense', villain: 'Everyone', story: 's', objectives: [], playable: true, best: 0 }],
		settings: { invert_pitch: true, missile_cam: true } };
	await p.evaluate((s) => window.skLauncher.show(s), state);
	await p.waitForTimeout(4500); // let the opening animation finish
	await p.screenshot({ path: out });
	await b.close();
	console.log('wrote', out, d.viewport);
})();
