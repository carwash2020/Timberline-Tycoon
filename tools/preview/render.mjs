// Screenshots of preview scenes (optional; needs Node and Playwright).
//   node tools/preview/render.mjs preview/trees.html            every camera view
//   node tools/preview/render.mjs preview/trees.html 2          just view 2
// Writes preview/<scene>-<view>.png. Set THREE_DIR to a local three.js
// package folder (node_modules/three) to render offline; otherwise three.js
// loads from the jsDelivr CDN like it does in a browser.
import { chromium } from "playwright";
import fs from "node:fs";
import path from "node:path";

const [, , htmlPath, onlyView, sizeArg] = process.argv;
if (!htmlPath) {
  console.error("usage: node tools/preview/render.mjs preview/<scene>.html [view] [WIDTHxHEIGHT]");
  process.exit(1);
}
const [width, height] = (sizeArg || "1280x800").split("x").map(Number);
const threeDir = process.env.THREE_DIR;
const executablePath = process.env.CHROMIUM_PATH || undefined;

const browser = await chromium.launch({
  executablePath,
  args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"],
});
const page = await browser.newPage({ viewport: { width, height } });
page.on("pageerror", (e) => console.error("page error:", e.message));
page.on("console", (m) => { if (m.type() === "error") console.error("console:", m.text()); });
if (threeDir) {
  await page.route(/cdn\.jsdelivr\.net\/npm\/three@[^/]+\/(.*)$/, (route) => {
    const rel = route.request().url().replace(/^.*?three@[^/]+\//, "");
    const file = path.join(threeDir, rel);
    if (!fs.existsSync(file)) return route.fulfill({ status: 404, body: "missing " + rel });
    route.fulfill({ status: 200, contentType: "application/javascript", body: fs.readFileSync(file) });
  });
}
await page.goto("file://" + path.resolve(htmlPath));
await page.waitForFunction(() => window.__ready === true, null, { timeout: 120000 });
const count = await page.evaluate(() => window.viewCount);
const base = htmlPath.replace(/\.html$/, "");
const views = onlyView ? [Number(onlyView)] : Array.from({ length: count }, (_, i) => i + 1);
for (const v of views) {
  await page.evaluate((i) => window.setView(i), v - 1);
  await page.waitForTimeout(400);
  const out = `${base}-${v}.png`;
  await page.screenshot({ path: out, timeout: 180000 }); // software rendering is slow on big scenes
  console.log(out);
}
await browser.close();
