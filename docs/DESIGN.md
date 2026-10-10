# Design

baible's pages start where polychrome's do: Swiss, what Josef Müller-Brockmann might have made of a
workshop on a screen. It is a starting point, not a rulebook. When the work needs something the
Swiss defaults don't give, make the change on purpose and record it under "Divergences" below.

The stylesheet is `app/assets/stylesheets/application.css`, taken from polychrome's base layer
(not its game stage).

## Paper and type

- White paper with black type. No dark theme, no rounded corners, no shadows or gradients.
- One typeface: Inter, a grotesk, vendored as a variable font in `app/assets/fonts/` under the
  SIL OFL (with its licence). Hierarchy comes from size and weight, never from colour.
- An 8px baseline. Body 16/24, h2 24/32, h1 48/56 with tight tracking; small labels 11–13px bold.
  The wordmark is the one heavy italic.
- Flush left, ragged right. Figures are tabular where they're compared (seeds, run times).

## Grid

- One column, at most 1200px wide, 24px gutters; forms at most 1000px, prose 64ch.
- Sections sit under a 2px black rule (`.window`, `.panel`), not in a box. Rows are separated by
  1px grey hairlines. Pictures sit in auto-filling grids of at least 144–176px.

## Colour

- Type is near-black on white. Controls are grey (`--control`): links, buttons, forms, picking.
- **Red is for spending ComfyUI's time** (`.generate`): Generate, and "Train in ComfyUI". Nothing
  else is red. In polychrome red marks game moves; here the "move" is reaching ComfyUI.
  "Queue for tonight" and "Train tonight" are grey: they spend nothing now, and so is "Lay out the
  sheet", which baible does itself.
- Alerts carry a red edge; notices an ink one.
- Generated images and their checkerboard are content, in their own colours.

## Geometry

| Thing | Shape |
| --- | --- |
| Image kind | Small black square before its name |
| Audio kind | Small black circle before its name |
| Sheet kind | Small outlined square before its name: arranged, not drawn |
| A subject or target with no pick | An outlined square plate (a `?`, or the subject's initial) |
| Audio with no picture | A filled black circle in the plate |
| Transparency | A light checkerboard behind the image |
| A canon pick | A heavy (3px) black frame inside the picture, and the word CANON in small caps |
| The current pick | The word CURRENT in small caps, no frame |
| The training run an entry uses | A small black square before its version |
| A warning in running text (a LoRA ComfyUI can't see) | A red edge on its left, as alerts have |
| A candidate still rendering | `…`, blinking in two steps (still, under reduced motion) |
| Something you can't press now (Generate with ComfyUI away) | Hatched, not just greyed |
| The current page in the masthead | A small black square before its name |

No emoji or pictographic glyphs. An arrow (→) is typography (the workflow outline uses it).

## Motion

Almost none: the candidate placeholder blinks while it waits. Strips update in place as files land
(a reloaded frame), without animation.

## Divergences

- **Red for Generate, not game moves.** baible has no game; the expensive action is the one that
  reaches ComfyUI, and that's what red marks. "Train in ComfyUI" is red too: it spends ComfyUI's
  time, for hours.
- **No palette, no stage.** polychrome's fifteen-colour palette, halftones, parallelograms and
  display type are its game stage, and stay there. baible keeps the plain base it was built on.
- **Plates without colour.** polychrome colours a plate by its subject's name so the Goblin stays
  green everywhere; baible's plates are outline only, since a subject's real colours are its pick.
