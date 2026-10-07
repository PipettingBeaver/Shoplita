# Shoplita — agent notes

Single-file userscript that saves prices/pieces from lolita shops and compares them. No build system, no package.json, not a git repository.

## Files
- `Shoplita.txt` is the canonical source. Edit only this.
- `Shoplita.user.js` (clean, for sharing) and `Shoplita.dev.user.js` (localhost update URLs) are generated; never edit them by hand. `tools/sync.sh` rebuilds both, `tools/dev.sh` also serves them.
- Keep the code ES5 (`var` + function declarations; no `let`/`const`, arrows, template literals, optional chaining) and verify with acorn.

## Dev loop
- `bash tools/dev.sh` watches `Shoplita.txt` and serves the folder at `http://127.0.0.1:8791` (port 8765 is often taken on this machine).
- Install `http://127.0.0.1:8791/Shoplita.dev.user.js` once in Tampermonkey; it shares `@name`/`@namespace` with the clean build, so updates replace in place. After an edit, use Tampermonkey's "Check for updates" (or reopen the URL).
- `bash tools/sync.sh` alone just regenerates the two `.user.js` copies.

## Verify changes
There are no in-repo tests. Harnesses live in `/tmp/opencode` and may not survive a reboot; recreate them if missing.
```
cp Shoplita.txt /tmp/opencode/lolita.js
node --check /tmp/opencode/lolita.js
npx --yes acorn@8 --ecma5 /tmp/opencode/lolita.js
node /tmp/opencode/test42.js    # 250-product logic suite (needs /tmp/opencode/42products.json fixture)
node /tmp/opencode/smoke42.js   # UI/storage/compare/collections/outfit smoke test
```
- The `module.exports` block at the end of the script is a Node test hook; keep it and export new internals worth testing.
- Harnesses stub `document`, `location`, `GM_*`, `localStorage`, and `URL`, then `require` the copied file.

## Data contract (breaking this loses user data)
- Storage is `GM_getValue`/`GM_setValue` with a `localStorage` fallback; keys are prefixed `shoplita.`.
- `migrateLegacyKeys()` copies old unprefixed keys (`savedInfo.v1`, `priority.v1`, …) and `normalizeSources()` stamps legacy records with `source: "42lolita.com"`. Never remove or reorder these migrations.
- Listing matching is multi-key (`listingKeys`): normalized `source|handle`, `source|url:<path>`, and a cross-domain `image:<url>` key. `recordsMatch`/`dedupeList` treat a match on any key as the same listing; `upsertRecord` and `mergeImport` use it, and `dedupeRecords()` collapses legacy duplicates on load (merging histories, newest `savedAt` wins). `source` aliases (`www.`, `m.`, `aliexpress.us`→`aliexpress.com`) are normalized. Never hand-roll these comparisons.
- The Saved-items panel collapses rows to one per listing via `collapseListingRows` (best color row, `colorCount` meta); Compare and CSV exports still use per-color rows (`buildSummaryRows`).
- `removeItemGroup` also strips the item key from every collection, so set counts stay accurate when listings are removed.
- Price history lives on the record as a compact `history` array (one `{savedAt, currency, variants:[{id,price,available}]}` per day, capped at 180). `upsertRecord`/`dedupeRecords` append via `pushHistory`/`mergeHistoryFrom`; `historyMatrix()` feeds the price-history TSV/CSV exports.
- Share format is `{format:"shoplita", version:2, ...}`. Import must keep accepting v1 `42lolita-userscript`, bare arrays, single records, and must merge priority/unavailable/collections/outfits.
- `priority` values are like timestamps (monotonic ms from `likeItem`), not counters; legacy numeric values are migrated in `normalizeSources`. Compare ranking/filter state is persisted inside `shoplita.compare.v1` alongside the A/B keys.

## Prices
- `normalize()` expects Shopify variant prices in **cents** and divides by 100; stored records, Compare, collections and outfits all work in **dollars**.
- Non-Shopify adapters build variants themselves, so multiply parsed page prices by 100 before calling `normalize()`.

## Sites / adapters
- `registerAdapter({id, matches, collect})` plus one `@match` line per site; `collectProduct()` picks the first match and Save/Like stay disabled when nothing matches (`adapterFor`).
- Shopify adapter: any store exposing `/products/<handle>.js` (covers 42Lolita).
- Devilinspired: parses the page's inline `window.skuMap`.
- My-Lolita-Dress: Cloudflare returns 403 to curl; only the generic DOM collector can work — verify in a real browser.
- AliExpress: `installAliExpressSniffer()` (called at document-start) wraps `fetch`/XHR to capture the PDP's own SKU API response (`skuBase`) — this is the only source of per-size prices on the new React PDP. Fallback order: captured API data → embedded `window.runParams`/`_d_c_` → DOM (`[class*="sku-item--property"]` / `[data-sku-col]` options, `[class*="price-default--current"]` price, `[class*="quantity--info"]` availability, slider/magnifier images upscaled via `aliexpressImageUrl`). Login/sync redirects block scripted requests — verify in a real browser.
- Amazon: pure DOM collector (`collectAmazon`). ASIN comes from `/dp/`, `/gp/product/`, `/gp/aw/d/`, `/d/`, `/product/` or `?asin=`; price is read from the core-price/apex/buybox selectors, JSON-LD `offers` (incl. `lowPrice`), or the generic fallback; variants are built as a color × size cross-product from `[id^="variation_"]` (single-dim fallback, base variant when no twister). Per-ASIN prices/availability are not fetched, so all combos carry the page price. Amazon serves bot interstitials to scripted requests — verify in a real browser.
- Adapters carry a `label` used by the Saved-items About list; add one when registering a new adapter.
- `@match` currently covers 42lolita.com, devilinspired.com, my-lolita-dress.com, `*.aliexpress.com`/`*.aliexpress.us`, and `*.amazon.*` storefronts (item pages).

## UI conventions
- Inline styles only; one injected stylesheet `#shoplita-saveinfo-styles`; CSS classes are prefixed `shoplita-`.
- Compare pickers use the custom `makeSearchableSelect` combobox (search + keyboard nav, one shared document click listener) — do not regress them to native `<select>`.
- `variantTypeName` strips color words from bundle labels, so per-color values like "Gray Blue Set" / "Dark Red Set" collapse into one Compare type ("Set") with colors as options. Records store `image` plus an `images` candidate array; Compare falls back through candidates on load error.
- `ui.v1` also stores `addToSet`, the default target set new saves/likes join (`Saved to "<set>"!`); deleting that set clears it.
- Liking from the Saved-items panel switches the list to Priority sort (persisted in `ui.sortBy`) so the liked row moves to the top; the "Sort by" toggle still lets users return to Recently added.
- Preserve aria attributes (`aria-expanded`/`aria-pressed`/`aria-live`, labels) and the `prefers-reduced-motion` handling.
- `@run-at document-start`: never touch `document.body` before `whenBodyReady`. The panel is bottom-right, minimizable, and must stay inside the viewport (max-height/width + wrapping).
