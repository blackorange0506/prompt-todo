// Playwright side of the frontend driver. Reads the plan from NAV_* environment variables
// (see scripts/appNavigation.sh), opens the app, logs in, walks the levels.
//
// Selectors from app.json: a value that starts with '#', '.', '[', '/', or contains a space or
// '>' is used as is (CSS / XPath); anything else means `[data-testid="<value>"]`.
//
// Exit codes: 0 ok · 1 error · 42 ambiguous row — a CHOOSE block is printed on stderr and the
// caller re-runs with APPNAV_<LEVEL>_PICK=<n> (the dispatcher passes it as NAV_LEVEL_i_PICK).
import { chromium } from 'playwright';

const env = process.env;
const log = (m) => process.stderr.write(`[appNavigation/frontend] ${m}\n`);
const warn = (m) => process.stderr.write(`[appNavigation/frontend WARN] ${m}\n`);
const sel = (v) => (!v ? '' : /^[#.\[/]|[\s>]/.test(v) ? v : `[data-testid="${v}"]`);
const loginOnly = process.argv.includes('--login-only');
const headless = env.NAV_HEADLESS === 'true';
const keepOpenSeconds = Number(env.APPNAV_KEEP_OPEN_SECONDS ?? (headless ? 0 : 300));

const levels = [];
for (let i = 1; i <= Number(env.NAV_LEVEL_COUNT || 0); i++) {
  levels.push({
    key: env[`NAV_LEVEL_${i}_KEY`],
    query: env[`NAV_LEVEL_${i}_QUERY`] || '',
    search: sel(env[`NAV_LEVEL_${i}_SEARCH`]),
    row: sel(env[`NAV_LEVEL_${i}_ROW`]),
    ready: sel(env[`NAV_LEVEL_${i}_READY`]),
    pick: Number(env[`NAV_LEVEL_${i}_PICK`] || 0),
  });
}

async function login(page) {
  const kind = env.NAV_LOGIN_KIND || 'none';
  const ready = sel(env.NAV_READY_SEL);
  if (kind === 'none' || env.NAV_MANUAL_LOGIN === '1') {
    if (env.NAV_MANUAL_LOGIN === '1' && ready) {
      log('manual login: waiting for the app to be ready');
      await page.locator(ready).first().waitFor({ timeout: 600000 });
    }
    return;
  }
  if (ready && (await page.locator(ready).first().isVisible().catch(() => false))) {
    log('already logged in');
    return;
  }
  const button = sel(env.NAV_LOGIN_BUTTON);
  const user = sel(env.NAV_LOGIN_USERNAME_SEL);
  const pass = sel(env.NAV_LOGIN_PASSWORD_SEL);
  const submit = sel(env.NAV_LOGIN_SUBMIT_SEL);
  if (button && (await page.locator(button).first().isVisible().catch(() => false))) {
    await page.locator(button).first().click();
  }
  await page.locator(user).first().waitFor({ timeout: 60000 });
  await page.locator(user).first().fill(env.NAV_USERNAME || '');
  await page.locator(pass).first().fill(env.NAV_PASSWORD || '');
  if (submit) await page.locator(submit).first().click();
  else await page.locator(pass).first().press('Enter');
  if (ready) await page.locator(ready).first().waitFor({ timeout: 60000 });
  log(`logged in as ${env.NAV_USERNAME}`);
}

async function walk(page, level, index) {
  if (level.search) {
    const s = page.locator(level.search).first();
    await s.waitFor({ timeout: 15000 });
    await s.fill(level.query);
  }
  const rows = page.locator(level.row).filter({ hasText: level.query });
  await rows.first().waitFor({ timeout: 15000 }).catch(() => {});
  const n = await rows.count();
  if (n === 0) {
    warn(`${level.key}: no row contains "${level.query}" — stopping here`);
    return false;
  }
  let which = 0;
  if (n > 1) {
    if (level.pick >= 1 && level.pick <= n) {
      which = level.pick - 1;
    } else {
      process.stderr.write(`[appNavigation] CHOOSE level=${level.key}\n`);
      for (let i = 0; i < n; i++) {
        const t = (await rows.nth(i).innerText()).replace(/\s+/g, ' ').trim();
        process.stderr.write(`  ${i + 1}) ${t}\n`);
      }
      process.stderr.write(`Re-run with APPNAV_${level.key.toUpperCase()}_PICK=<n>\n`);
      process.exit(42);
    }
  }
  await rows.nth(which).click();
  if (level.ready) await page.locator(level.ready).first().waitFor({ timeout: 15000 });
  log(`level ${index}: ${level.key} → "${level.query}"${n > 1 ? ` (pick ${which + 1} of ${n})` : ''}`);
  return true;
}

const browser = await chromium.launch({ headless });
const page = await browser.newPage();
let rc = 0;
try {
  log(`open ${env.NAV_BASE_URL}`);
  await page.goto(env.NAV_BASE_URL, { waitUntil: 'domcontentloaded' });
  await login(page);
  if (!loginOnly) {
    for (let i = 0; i < levels.length; i++) {
      if (!(await walk(page, levels[i], i + 1))) break;
    }
  }
  process.stdout.write(`URL: ${page.url()}\n`);
  if (keepOpenSeconds > 0) {
    log(`browser stays open for ${keepOpenSeconds}s (APPNAV_KEEP_OPEN_SECONDS)`);
    await new Promise((r) => setTimeout(r, keepOpenSeconds * 1000));
  }
} catch (e) {
  rc = 1;
  process.stderr.write(`[appNavigation/frontend ERROR] ${e.message}\n`);
} finally {
  await browser.close().catch(() => {});
}
process.exit(rc);
