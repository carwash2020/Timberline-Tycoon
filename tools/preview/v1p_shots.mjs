// Lane P: screenshots every v1p_gui HTML page in a folder at its own size.
//   node tools/preview/v1p_shots.mjs <dir> [filter]
// Run from $RENDER_HOME (where Playwright is linked), as shoot.sh does.
import { chromium } from "playwright";
import fs from "node:fs";
import path from "node:path";

const dir = path.resolve(process.argv[2]);
const filter = process.argv[3] || "";
const browser = await chromium.launch();
for (const name of fs.readdirSync(dir)) {
	if (!name.endsWith(".html") || !name.includes(filter)) continue;
	const file = path.join(dir, name);
	const html = fs.readFileSync(file, "utf8");
	const m = html.match(/body\{width:(\d+)px;height:(\d+)px/);
	const [w, h] = m ? [Number(m[1]), Number(m[2])] : [1280, 720];
	const page = await browser.newPage({ viewport: { width: w, height: h } });
	await page.goto("file://" + file);
	await page.evaluate(() => document.fonts.ready);
	const out = file.replace(/\.html$/, ".png");
	await page.screenshot({ path: out, omitBackground: name.includes("-alpha") });
	await page.close();
	console.log(out);
}
await browser.close();
