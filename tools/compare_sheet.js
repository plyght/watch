// Comparison sheet: for each region, reference | render | reference with the
// render's outlines traced on it, all at the same millimetre scale.
//
// node tools/compare_sheet.js REF.jpg refCx refCy refMmPerPx REN.png renCx renCy renMmPerPx EDGES.png OUT.png
const {chromium} = require('playwright');
const fs = require('fs');
const [ref, rcx, rcy, rmm, ren, ncx, ncy, nmm, edges, out] = process.argv.slice(2);
const b64 = (f, t) => `data:${t};base64,` + fs.readFileSync(f).toString('base64');
const R = b64(ref, 'image/jpeg'), N = b64(ren, 'image/png'), E = b64(edges, 'image/png');
const CELL = 560;
// Regions in mm: [label, centre x, centre y, half width]
const regions = [['whole watch', 0, 0, 33], ['dial', 0, 0, 18.6], ['lug, 1:30', 12.5, 19.5, 6.5], ['bracelet', 0, -30, 10]];
function crop(src, imgW, cx, cy, mmpx, x, y, half) {
  const scale = CELL / (2 * half / mmpx);
  const left = -(cx + (x - half) / mmpx) * scale, top = -(cy - (y + half) / mmpx) * scale;
  return `<img src="${src}" style="position:absolute;left:${left}px;top:${top}px;width:${imgW * scale}px">`;
}
(async () => {
  const br = await chromium.launch();
  const p = await br.newPage({viewport: {width: CELL * 3 + 40, height: 400}});
  // Natural widths of the two images.
  await p.setContent(`<img id=a src="${R}"><img id=b src="${N}">`, {waitUntil: 'load'});
  const [rw, nw] = await p.evaluate(() => [a.naturalWidth, b.naturalWidth]);
  let rows = '';
  for (const [label, x, y, half] of regions) {
    const cell = inner => `<div style="position:relative;width:${CELL}px;height:${CELL}px;overflow:hidden;background:#fff">${inner}</div>`;
    rows += `<div style="font:600 20px Inter,sans-serif;margin:18px 0 6px">${label} <span style="font-weight:400;color:#777">(${(2 * half).toFixed(0)} mm across)</span></div>
      <div style="display:flex;gap:10px">${cell(crop(R, rw, +rcx, +rcy, +rmm, x, y, half))}${cell(crop(N, nw, +ncx, +ncy, +nmm, x, y, half))}${cell(crop(R, rw, +rcx, +rcy, +rmm, x, y, half) + crop(E, nw, +ncx, +ncy, +nmm, x, y, half))}</div>`;
  }
  const html = `<body style="margin:0;padding:10px;background:#f4f4f2;width:${CELL * 3 + 20}px">
    <div style="display:flex;gap:10px;font:600 22px Inter,sans-serif"><div style="width:${CELL}px">reference photo</div><div style="width:${CELL}px">render</div><div style="width:${CELL}px">photo + render outlines</div></div>${rows}</body>`;
  await p.setContent(html, {waitUntil: 'load'});
  await p.waitForTimeout(500);
  await p.screenshot({path: out, fullPage: true});
  await br.close();
})();
