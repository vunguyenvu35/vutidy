// Render SVG logo -> PNG bằng Chromium (Playwright).
// Cần Playwright: PLAYWRIGHT=/đường/dẫn/tới/node_modules/playwright/index.mjs
// usage: node render.mjs '[{"svg":"logo-mark.svg","out":"logo-mark-1024.png","w":1024,"h":1024,"pad":0,"bg":"#fff"}]'
import fs from 'node:fs'
import path from 'node:path'
import {fileURLToPath, pathToFileURL} from 'node:url'

const {chromium} = await import(pathToFileURL(process.env.PLAYWRIGHT ?? 'playwright').href.replace('file:///playwright', 'playwright'))
const here = path.dirname(fileURLToPath(import.meta.url))
const jobs = JSON.parse(process.argv[2])
const browser = await chromium.launch()
for (const {svg, out, w, h, pad = 0, bg} of jobs) {
  const src = fs.readFileSync(path.join(here, svg), 'utf8')
  const page = await browser.newPage({viewport: {width: w, height: h}, deviceScaleFactor: 1})
  const sized = src.replace('<svg ', `<svg style="position:absolute;left:${pad}px;top:${pad}px;width:${w - 2 * pad}px;height:${h - 2 * pad}px" `)
  await page.setContent(`<html><body style="margin:0;background:${bg ?? 'transparent'}">${sized}</body></html>`)
  await page.screenshot({path: path.resolve(here, out), omitBackground: !bg})
  await page.close()
}
await browser.close()
