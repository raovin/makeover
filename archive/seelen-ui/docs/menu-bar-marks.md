# Menu-bar mark (top-left logo)

The top-left menu-bar mark (where macOS shows the Apple logo) is drawn entirely in
CSS by the `macos-glass` theme. The Seelen toolbar item `macmakeover-apple-menu`
just returns the text `"Apple"`; the theme hides that text and paints a custom mark
with a `::before` pseudo-element.

- Theme file (source of truth): `config/seelen/themes/macos-glass/styles/fancy-toolbar.css`
- Live copy Seelen reads: `%APPDATA%\com.seelen.seelen-ui\themes\macos-glass\styles\fancy-toolbar.css`
- Selector to edit: `.ft-bar-left > .ft-bar-item:first-child .ft-bar-item-content::before`
  (and the matching `:hover` rule just below it)

The mark is just visuals. The clickable zone that opens the Apple menu is handled
separately by `scripts/start-hot-corners.ps1`, so changing the mark never affects
click behaviour.

## How to swap the mark

1. In `fancy-toolbar.css`, replace the `background`, `-webkit-mask`, `mask`, and
   `filter` lines of the `::before` rule with one option below (and update the
   `:hover` `filter` to match the glow colour).
2. Copy the file to the live path above.
3. Seelen hot-reloads the theme — no restart needed. Verify at the top-left.

The `command` option is special: it paints a `⌘` glyph as gradient text instead of
an SVG mask, so replace the whole `::before` body with its block.

## Currently active: hex core

A glowing teal->cyan->blue hexagon wireframe with a center node and three spokes
(reads as an isometric cube). This is what ships in `fancy-toolbar.css`.

```css
width: 20px;
height: 19px;
background: linear-gradient(140deg, #46f0b4 0%, #22d3ee 58%, #3a93ff 100%);
-webkit-mask: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath fill='none' stroke='black' stroke-width='1.8' stroke-linejoin='round' d='M12 1.5 L21.1 6.75 L21.1 17.25 L12 22.5 L2.9 17.25 L2.9 6.75 Z'/%3E%3Cpath fill='none' stroke='black' stroke-width='1.1' d='M12 12 L12 1.5 M12 12 L21.1 17.25 M12 12 L2.9 17.25'/%3E%3Ccircle fill='black' cx='12' cy='12' r='2.6'/%3E%3C/svg%3E") center / contain no-repeat;
mask: <same url as -webkit-mask>;
filter: drop-shadow(0 0 3px rgba(52, 230, 168, 0.7)) drop-shadow(0 0 8px rgba(43, 212, 255, 0.5));
/* hover: drop-shadow(0 0 4px rgba(70,240,180,0.95)) drop-shadow(0 0 11px rgba(43,212,255,0.7)); */
```

## Option: crystal (faceted gem)

Iridescent cyan->violet->pink gem silhouette.

```css
width: 18px;
height: 19px;
background: linear-gradient(135deg, #5ef0ff 0%, #7b6cff 50%, #ff6ec7 100%);
-webkit-mask: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath fill='black' d='M5 7 L19 7 L22.5 12 L12 22.5 L1.5 12 Z'/%3E%3C/svg%3E") center / contain no-repeat;
mask: <same url>;
filter: drop-shadow(0 0 3px rgba(123, 108, 255, 0.7)) drop-shadow(0 0 8px rgba(255, 110, 199, 0.4));
/* hover: drop-shadow(0 0 4px rgba(123,108,255,0.95)) drop-shadow(0 0 11px rgba(255,110,199,0.6)); */
```

## Option: flame

Bold base-warm to tip-cool flame.

```css
width: 17px;
height: 20px;
background: linear-gradient(0deg, #ffb347 0%, #ff5d7a 50%, #9b5cff 100%);
-webkit-mask: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath fill='black' d='M12 1 C16 8 21 11 18.5 17 C16.8 21 14 23 12 23 C10 23 7.2 21 5.5 17 C3.8 12.5 8 11 9 7 C11 10 10 4 12 1 Z'/%3E%3C/svg%3E") center / contain no-repeat;
mask: <same url>;
filter: drop-shadow(0 0 3px rgba(255, 93, 122, 0.7)) drop-shadow(0 0 8px rgba(155, 92, 255, 0.4));
/* hover: drop-shadow(0 0 4px rgba(255,93,122,0.95)) drop-shadow(0 0 11px rgba(155,92,255,0.6)); */
```

## Option: orbit (atom)

Cyan->blue twin-ring orbit with a center nucleus.

```css
width: 21px;
height: 19px;
background: linear-gradient(135deg, #2be0ff 0%, #5b8cff 100%);
-webkit-mask: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cg fill='none' stroke='black' stroke-width='1.7'%3E%3Cellipse cx='12' cy='12' rx='10.6' ry='4.2' transform='rotate(32 12 12)'/%3E%3Cellipse cx='12' cy='12' rx='10.6' ry='4.2' transform='rotate(-32 12 12)'/%3E%3C/g%3E%3Ccircle fill='black' cx='12' cy='12' r='2.7'/%3E%3C/svg%3E") center / contain no-repeat;
mask: <same url>;
filter: drop-shadow(0 0 3px rgba(43, 196, 255, 0.7)) drop-shadow(0 0 8px rgba(91, 140, 255, 0.4));
/* hover: drop-shadow(0 0 4px rgba(43,196,255,0.95)) drop-shadow(0 0 11px rgba(91,140,255,0.6)); */
```

## Option: command (⌘ glyph)

Iconic Mac command key as gradient text. Replace the WHOLE `::before` body with this
(it uses gradient text, not an SVG mask):

```css
.ft-bar-left > .ft-bar-item:first-child .ft-bar-item-content::before {
  content: "⌘";
  display: block;
  font-size: 16px;
  font-weight: 600;
  line-height: 19px;
  background: linear-gradient(135deg, #8bd3ff 0%, #3a7bff 100%);
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
  -webkit-mask: none;
  mask: none;
  filter: drop-shadow(0 0 3px rgba(58, 123, 255, 0.65));
  transition: filter 160ms ease, transform 160ms ease;
}
```

The colour gradients above are independent of the shape — mix any `background`
gradient with any mask to retint a mark.
