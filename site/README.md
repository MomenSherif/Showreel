# Showreel landing page

A static page made of `index.html`, `styles.css` (which imports `tokens.css` and `base.css`), `main.js`, and `assets/`. There is no build step and no framework. The only outside request is the Geologica font from Google Fonts.

The design is Hallmark's Vantage theme (the skill is in `.claude/skills/hallmark` at the repo root. Its `--render` check needs Puppeteer, which git ignores: run `npm install puppeteer` in `.claude/skills/hallmark/scripts/` once on a fresh clone). The first lines of `styles.css` record every design decision. To check the page again, run this from `Showreel/`:

```sh
node .claude/skills/hallmark/scripts/sloplint.mjs site/index.html --genre modern-minimal --render
```

## Preview

```sh
cd site
python3 -m http.server 8765
# open http://localhost:8765
```

Open it through a server rather than as a `file://` URL, so the video and the images load the same way they will once it's deployed.

## The product tour video

The hero plays `assets/tour.mp4`, which is the Motion film "Showreel product tour" exported from claude.ai and re-encoded for the web. It went from 20.6 MB to 2.7 MB, still 1920×1080 at 60 fps and 35 s, with fast start so it begins playing before it finishes loading. `assets/tour-poster.webp` is its first frame. To replace it after changing the film:

```sh
# from site/, after Export on the film page saved ~/Downloads/showreel-product-tour.mp4
ffmpeg -i ~/Downloads/showreel-product-tour.mp4 -c:v libx264 -preset slow -crf 24 -pix_fmt yuv420p \
  -movflags +faststart -c:a aac -b:a 128k assets/tour.mp4
ffmpeg -ss 0.5 -i assets/tour.mp4 -frames:v 1 /tmp/poster.png && cwebp -q 82 /tmp/poster.png -o assets/tour-poster.webp
```

The video plays with sound while it's on screen. Browsers refuse sound until the visitor has clicked or pressed a key, so until then it plays muted and the sound comes on with the first click or key press anywhere on the page. It pauses when it scrolls away and with Reduce Motion on, never on hover. The Pause and Turn sound off buttons sit under it. If the file is missing, the first frame shows and both buttons stay hidden.

## Links

The Download buttons, the Donate link, and the GitHub icon in the nav read three constants at the top of `main.js`:

```js
const DOWNLOAD_URL = '#download'; // a .dmg or a store page
const DONATE_URL = '#donate';     // GitHub Sponsors, Buy Me a Coffee, Ko-fi, …
const GITHUB_URL = '#github';     // the repository
```

Set them before publishing. A download link that ends in `.dmg`, `.zip`, or `.pkg` also gets the `download` attribute. Donate and GitHub open in a new tab once they're `https://` links.

## Screenshots

`assets/shots/` holds dark WebP captures of the real app, taken in the steel sample look so they sit on the Vantage page. `APP_SEED_LOOK=steel` gives the sample projects grey recordings on the Slate gradient. It only affects seeded test stores. To retake them:

```sh
# from Showreel/
APP_SEED_LOOK=steel APP_ACCENT=graphite tools/snap.sh     # writes /tmp/Showreel-shots/*.png
cwebp -q 82 /tmp/Showreel-shots/editor-dark.png -o site/assets/shots/editor-dark.webp
```

`assets/raw-window.webp` (the sample recording cropped to its window: `cwebp -crop 168 118 1264 756` of a full frame) and `assets/camera-frame.webp` are frames of the sample recording and its camera track (from `/tmp/Showreel-projects/*/screen.mov` and `camera.mov`). The before-and-after uses them. The `*-light.webp` files and `assets/cursors/` aren't used any more and can be deleted.

## Deploy

The whole `site/` folder is the site. Any static host works.

- **GitHub Pages:** push the repo, then go to Settings > Pages and pick the branch and the `/site` folder. You can also copy `site/` to a `gh-pages` branch.
- **Cloudflare Pages:** create a project from the repo, with no build command and `site` as the output directory. Or run `npx wrangler pages deploy site`.
- **Netlify:** drag the `site` folder onto app.netlify.com/drop. Or connect the repo, with no build command and `site` as the publish directory.

The whole site is about 5 MB (less once the unused light screenshots go), and `tour.mp4` is 2.7 MB of that.
