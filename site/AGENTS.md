# Analytics Tracking — Mixpanel

The Showreel landing page (this `site/` folder) uses **Mixpanel** for analytics. Do not add other analytics tools without the owner asking. The Mac app itself (`../Sources/`) has **no analytics** on purpose: it's local, offline, no accounts. Don't add tracking there.

## Before you add or change tracking

- [ ] Read the tracking plan below. Reuse an event and add a property rather than making a near-duplicate.
- [ ] No CDP: the page talks to Mixpanel directly.
- [ ] Privacy: the library never loads for visitors who send Global Privacy Control or Do Not Track (`optedOut` in `main.js`). Keep that. No consent banner yet; if one is added, initialize with `opt_out_tracking_by_default: true` and call `mixpanel.opt_in_tracking()` on accept.

## Tech stack

| Detail | Value |
|---|---|
| Platform | Static HTML/CSS/JS, no build step, no framework |
| Mixpanel SDK | mixpanel-js from `cdn.mxpnl.com/libs/mixpanel-2-latest.min.js`, loaded by a stub in `main.js` |
| Tracking method | Client-side, `api_transport: 'sendBeacon'`, `persistence: 'localStorage'` |
| Autocapture | Off (`autocapture: false`); page views on (`track_pageview: true`) |
| CDP | None |
| Token location | `MIXPANEL_TOKEN` at the top of `main.js`. It's a public project token, so it's fine in client code. Empty turns analytics off. |
| Host | `MIXPANEL_HOST`; switch to `https://api-eu.mixpanel.com` for an EU-resident project |

## Initialization

Once, in the `track` IIFE near the top of `site/main.js`. Every event goes through the `track(event, props)` function it returns. Don't call `window.mixpanel` directly and don't initialize a second instance.

## Identity

None. Visitors are anonymous (Mixpanel's `$device_id` in local storage). There are no accounts, so never call `identify()`, `people.set()`, or `reset()`.

## Tracking plan

Naming: events are `snake_case` `object_verb` in the past tense; properties are `snake_case`; values are lowercase and from a fixed set. Never build event names at runtime. Leave a property out rather than sending `null` or `""`.

| Event | Trigger | Properties | Where |
|---|---|---|---|
| `$mp_web_page_view` | Page opens (automatic) | Mixpanel defaults | init config |
| `section_viewed` | Section reaches mid-screen, once per section per visit | `section` | `main.js`, section_viewed block |
| `style_demo_used` | First use of each style control, once per control per visit | `control` | `main.js`, compare/controls block |
| `caption_example_viewed` | Caption tab picked (click or arrow key) | `example` | `main.js`, `[data-switch]` block |
| `faq_opened` | FAQ `<details>` opened | `question` | `main.js`, end of file |
| `download_clicked` | **Key event.** Any `[data-download]` link | `placement`, `url` | `main.js`, links block |
| `donate_clicked` | Any `[data-donate]` link | `placement`, `url` | `main.js`, links block |
| `github_clicked` | Any `[data-github]` link | `placement`, `url` | `main.js`, links block |

## Adding an event

1. Check the table above, then name it by the conventions.
2. Call `track('event_name', { ... })` in the handler for the action. Throttle anything that can fire continuously (sliders, scroll) to once per visit.
3. Add a row to the table above.
4. Verify it: serve the page (`python3 -m http.server 8765`), trigger the event, and check Mixpanel > Live View, or the `api-js.mixpanel.com/track` request in DevTools. Filter local test data out with `current_domain` ≠ `localhost`.

## Don't

- Track PII. The page has no forms; keep it that way for analytics.
- Turn autocapture back on without a reason; it floods the project with unnamed click events.
- Fire events in loops or on every `input` event.
