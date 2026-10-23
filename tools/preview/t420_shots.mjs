// T420: screenshots the picker pages t420_gui writes, plus a close-up of the Xbox focus ring
// on a card corner (device scale 4). Run from $RENDER_HOME (Playwright is linked there):
//   node t420_shots.mjs <dir>
import { chromium } from "playwright";
import fs from "node:fs";
import path from "node:path";

const dir = path.resolve(process.argv[2]);
const browser = await chromium.launch();
for (const name of fs.readdirSync(dir)) {
	if (!name.startsWith("picker-") || !name.endsWith(".html")) continue;
	const file = path.join(dir, name);
	const html = fs.readFileSync(file, "utf8");
	const m = html.match(/body\{width:(\d+)px;height:(\d+)px/);
	const [w, h] = m ? [Number(m[1]), Number(m[2])] : [1280, 720];
	const page = await browser.newPage({ viewport: { width: w, height: h } });
	await page.goto("file://" + file);
	await page.evaluate(() => document.fonts.ready);
	await page.screenshot({ path: file.replace(/\.html$/, ".png") });
	if (name.startsWith("picker-xbox")) {
		// The ring is the last-drawn FocusRing; find the selected card by its ring.
		const box = await page.evaluate(() => {
			const ring = [...document.querySelectorAll('[data-name="FocusRing"]')][0];
			const r = ring.getBoundingClientRect();
			return { x: r.x, y: r.y, w: r.width, h: r.height };
		});
		const close = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 4 });
		await close.goto("file://" + file);
		await close.evaluate(() => document.fonts.ready);
		await close.screenshot({
			path: file.replace(/picker-xbox-[0-9x]+\.html$/, "picker-xbox-ring-closeup.png"),
			clip: { x: Math.max(0, box.x - 24), y: Math.max(0, box.y - 24), width: 120, height: 90 },
		});
		await close.close();
		console.log("ring box", JSON.stringify(box));
	}
	await page.close();
	console.log(file.replace(/\.html$/, ".png"));
}
await browser.close();
