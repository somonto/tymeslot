// Somonto fork: screenshots of the booking flow (Quill + Somonto style layer) at 320, 375, 768 and 1440 px.
// Runs in .github/workflows/somonto-sicht.yml against the built image with seed.exs; output in ./sicht-ausgabe.
import { chromium } from "playwright";
import { readFileSync, mkdirSync } from "node:fs";

const BASIS = process.env.SICHT_URL || "http://localhost:4000/probe";
const HIER = new URL(".", import.meta.url).pathname;
const AUS = "sicht-ausgabe";
mkdirSync(AUS, { recursive: true });
const dateien = {
  "/assets/somonto-stil.css": ["somonto-stil.css", "text/css"],
  "/assets/somonto-golos-text-variable.woff2": ["somonto-golos-text-variable.woff2", "font/woff2"],
};
const ANKER = "#name=Anna+Muster&email=anna%40tischlerei-muster.at&company=Tischlerei+Muster+GmbH&phone=%2B43+664+1234567";

async function lauf(browser, breite, { anker = "" } = {}) {
  const page = await browser.newPage({ viewport: { width: breite, height: breite < 768 ? 800 : 900 }, deviceScaleFactor: 2, locale: "de-AT", timezoneId: "Europe/Vienna" });
  for (const [pfad, [datei, typ]] of Object.entries(dateien)) {
    await page.route("**" + pfad, (route) => route.fulfill({ body: readFileSync(HIER + datei), contentType: typ }));
  }
  const name = (schritt) => `${AUS}/${anker ? "vorausgefuellt-" : ""}${breite}-${schritt}.png`;
  const bild = async (schritt) => { await page.waitForTimeout(400); await page.screenshot({ path: name(schritt), fullPage: true }); };
  // Zeilenumbrüche messen (eine Zeile = Höhe < 1,6 × Zeilenhöhe): Berater-Zeile, Überschriften, Beschriftungen, Knöpfe.
  const messen = () => page.evaluate(() => [...document.querySelectorAll(".schedule-organizer__greeting, h1, h2, h3, label, button")].filter((e) => e.offsetParent).map((e) => {
    const s = getComputedStyle(e); const lh = parseFloat(s.lineHeight) || parseFloat(s.fontSize) * 1.2;
    return { text: e.innerText.trim().slice(0, 60), zeilen: Math.round(e.getBoundingClientRect().height / lh) };
  }).filter((z) => z.text && z.zeilen > 1));
  const mehrzeilig = [];
  page.on("pageerror", (e) => console.error("pageerror", e.message));
  try {
  await page.goto(`${BASIS}?theme=1&locale=de${anker}`, { waitUntil: "networkidle" });
  await page.addStyleTag({ url: "/assets/somonto-stil.css" });
  const tag = page.locator("[data-fact='date']:not([disabled])").filter({ visible: true });
  const zeiten = page.locator("[data-fact='time']:not([disabled]), [data-fact='slot']:not([disabled])").filter({ visible: true });
  await tag.or(zeiten).first().waitFor({ timeout: 30000 });
  await bild("1-kalender");
  mehrzeilig.push(...(await messen()));
  // Handy: die Wochenleiste wählt den ersten freien Tag selbst, die Zeiten stehen schon da.
  if (!(await zeiten.count())) await tag.nth(1).click();
  const zeit = zeiten.first();
  await zeit.waitFor({ timeout: 15000 });
  await zeit.click();
  await bild("2-uhrzeit");
  await page.locator("[data-testid='next-step']").filter({ visible: true }).first().click();
  for (const seite of ["1", "2"]) {
    await page.waitForSelector(`[data-details-page='${seite}']`, { timeout: 15000 });
    await bild(`${2 + Number(seite)}-angaben-seite-${seite}`);
    mehrzeilig.push(...(await messen()));
    if (!anker) {
      for (const feld of await page.locator(`[data-details-page='${seite}'] input:visible`).all()) {
        if ((await feld.inputValue()) !== "") continue;
        const typ = (await feld.getAttribute("type")) || "text";
        const n = (await feld.getAttribute("name")) || "";
        const wert = typ === "email" ? "anna@tischlerei-muster.at" : typ === "tel" ? "+43 664 1234567" : n === "booking[name]" ? "Anna Muster" : "Tischlerei Muster GmbH";
        await feld.fill(wert);
      }
    }
    await page.locator("[data-testid='details-next']").filter({ visible: true }).first().click();
  }
  await page.waitForSelector("[data-details-page='3']", { timeout: 15000 });
  await bild("5-uebersicht");
  mehrzeilig.push(...(await messen()));
  } catch (e) {
    await page.screenshot({ path: name("fehler"), fullPage: true }).catch(() => {});
    console.error("TEXT", breite, (await page.innerText("body").catch(() => "")).slice(0, 1500));
    await page.close();
    throw e;
  }
  await page.close();
  return { breite, anker: Boolean(anker), mehrzeilig };
}

const browser = await chromium.launch();
const bericht = [];
let fehler = 0;
for (const [b, o] of [[320], [375], [768], [1440], [375, { anker: ANKER }]]) {
  try { bericht.push(await lauf(browser, b, o)); } catch (e) { fehler++; bericht.push({ breite: b, fehler: String(e.message).split("\n")[0] }); }
}
await browser.close();
console.log(JSON.stringify(bericht, null, 1));
process.exitCode = fehler ? 1 : 0;
