# Viper website

A one-page product site for the Viper macOS app. Vanilla JavaScript, Vite and Three.js. All fonts and assets are served locally, with no analytics or remote calls.

## Run

```sh
npm install
npm run dev
```

`npm run build` writes a static bundle to `dist/`.

## Design

Type: General Sans Semibold for headings (Medium for buttons and navigation) and Gambetta Regular for text, both from Fontshare under the ITF Free Font License (files and licenses in `src/fonts`). Geist Mono is used for the small index labels.


A charcoal page with dark cards, one cream card and a single orange accent. Every illustration is an isometric line drawing in three.js: faces are filled with the card colour so hidden lines drop out, like a pen drawing. Orange marks the one thing each tool asks you to decide on.

- `src/scenes.js`: one WebGL renderer draws every illustration into the rectangle of its `.art` placeholder, so the page uses a single GL context.
- `src/content.js`: tool, review-step and screenshot copy. Keep it factual and in line with the app's README.
- Tool cards turn to paper on hover or focus, and their drawings re-ink to match.
- The review drawing is driven by scroll: the orange cube climbs to whichever of the eight steps is in view.
- The Quit button in "Background activity" switches the drawing and the list next to it.

The screens in `public/images` are Viper 1.0 screens redrawn in the site's theme, with the app's real text and data. They're built from `design/screens/screens.html`; run `node design/screens/render.mjs` to re-render them. The original captures are kept in `design/screens/originals`. The drawings hold still when the system asks for reduced motion.
