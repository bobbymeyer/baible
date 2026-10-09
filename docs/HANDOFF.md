# baible — Handoff

A tool for rapidly and consistently making the assets of a world: images and audio, generated in
ComfyUI from layered recipes, picked by a person, and handed on as files. Rails app.

This document is the design contract. Read it before writing code. Where it conflicts with a
shortcut, the document wins until Bobby changes it.

## 1. What it is

- A workshop for one person or a small team. Everyone signed in sees every project.
- A **project** is a world or a setting. Its house style is the first layer of everything made in it.
- An **entry** is one thing in that world across every kind it's made in: Cid, whose sprite,
  portrait and key art are each a subject of a different kind. The entries are the project's
  bible: each has lore for people and a look that every image of it carries.
- Every asset is made the same way: a **recipe** composed in layers, a **batch** of candidates in
  ComfyUI (each its own seed), and a **pick**. The pick keeps how it was made, exactly.
- Images (any ComfyUI image model the app can recognise, see "Workflows") and audio (ACE-Step).
- It came out of polychrome, a JRPG tabletop app, whose asset pipeline it is. polychrome is still
  its first customer: it makes polychrome's art and music. Both projects keep their own scope.

### Non-goals

- Not a game, and no knowledge of any game. baible has no idea what a monster, a book or a beat
  is; polychrome's kinds are just kinds a project can have.
- No API between baible and polychrome (or anything else). Assets leave as files (section 7).
- No asset library or DAM features: tagging, search, collections, versions beyond the current pick.
  An entry gathers what depicts one thing; it is not a folder or a tag.
- No training (LoRAs come from elsewhere), no inpainting editor, no image editing.
- Not multi-tenant. No per-project permissions, no sign-up page.

## 2. Data model

```
Project ─┬─ Kind ──────────┐            (a kind belongs to a project)
         ├─ Entry ─────────┤            (an entry belongs to a project; the bible)
         └─ Subject ───────┴─ Variant   (a subject belongs to a project, one of its kinds and maybe an entry)
                Subject / Variant ─── Batch ─── Candidate        (rounds of generation)
                Subject / Variant ─── Pick (one per target)      (the chosen file)
SiteSetting (one row)   User ─ Session
```

| Model | What | Columns that matter |
| --- | --- | --- |
| `Project` | A world or setting; the top layer | `name` (unique), `description` (never in a prompt), `style`, `negative`, `model`, `loras`, `sound` |
| `Kind` | A kind of asset in a project, named freely ("Creature", "Portrait", "Map", "Theme music"); the middle layer | `medium` (`image` \| `audio`), `prompt` (the framing), `negative`, `width`, `height`, `transparent`, `model`, `loras`, `seconds`, `variant_presets` |
| `Entry` | One thing in the world across kinds (Cid; the harbour town); the entry layer, between kind and subject | `name` (unique in its project), `look`, `loras`, `lore` (never in a prompt) |
| `Subject` | The thing made: a goblin, Cid, the harbour town, its theme; the subject layer | `kind`, `entry` (optional), `name` (unique in its kind), `notes`, `model`, `loras`, `lyrics`, `seconds` |
| `Variant` | A detail layer after a subject ("happy": "smiling happily") | `name` (unique in its subject), `prompt` |
| `Batch` | One round for a **target**: a subject (`variant` nil) or one of its variants | `recipe` (frozen at start), `status`, `error`, `submitted_at` |
| `Candidate` | One ComfyUI prompt in a batch, with its own seed, and the file it made | `seed`, `comfy_prompt_id`, `status`, `transparent`, `run_seconds`, attached `file` |
| `Pick` | The chosen file for a target, and how it was made. One per target; picking again replaces it | `seed`, `prompt`, `recipe`, `run_seconds`, attached `file` |
| `SiteSetting` | Where ComfyUI and the language model are, default models, draft tuning | see section 8 |

- A new project starts with the kinds in `config/comfy.yml` (`kinds`) unless asked not to; each is
  editable and removable. A kind with subjects can't be removed or change medium.
- A new subject starts with its kind's `variant_presets` as variants (a portrait's expressions).
- A subject's entry is one of its own project's. Deleting an entry keeps its subjects, unlinked.
- JSON columns hold LoRA stacks (`[{ "name", "strength", "on" }]`, cleaned by `ArtDirection.loras`)
  and recipes.
- Foreign keys are plain; the models clean up (`dependent:`).

## 3. The layered recipe

Everything ComfyUI needs apart from the seed is composed from up to five layers, top to bottom
(`Subject#recipe`, `Subject#layers`):

| Layer | Image | Audio |
| --- | --- | --- |
| Project | `style`, `negative`, `model`, `loras` | `sound` |
| Kind | `prompt` (framing), `negative`, size, `transparent`, `model`, `loras` | `prompt` (tags), `seconds`, `model` |
| Entry, when the subject has one | `look`, `loras` | nothing |
| Subject | its name and `notes`, `model`, `loras` | `notes` (as tags), `lyrics`, `seconds`, `model` |
| Variant | `prompt` | `prompt` |

- **Prompt:** the model family's quality words (image only), then each layer's words in order
  (`ArtDirection.compose`). The parts are kept in the recipe (`parts`) so the subject alone can be
  rewritten and the prompt put back together.
- **The entry's look** is what stays true in every picture of it (face, build, marks, the clothes
  it's known by). It goes in word for word, never rewritten, so the same words reach every image
  of it whatever its kind; what it looks like in one picture (wet, wounded) belongs to the subject
  or a variant. A look isn't a sound: audio has no entry layer, and an audio subject joins an
  entry only to sit on its page. Recipes from before entries have no `entry` part.
- **Negative** (image): the family's negative words, the project's, the kind's; empty when the
  family doesn't use one (CFG 1).
- **Model:** the lowest layer that names one wins, then the default (`SiteSetting`, then
  `config/comfy.yml`). Audio skips the project (its model is an image model): subject, kind, then
  ACE-Step's checkpoint (`music.model`).
- **LoRAs** (image) stack in layer order, project first (an entry's come after the kind's: a LoRA
  trained on that character, say). A lower layer naming the same LoRA changes
  its strength in place, or switches it off. Switched-off LoRAs stay in the recipe, for the record.
- **Size** (image) is the kind's, scaled into the family's trained range, keeping its shape.
- **Length** (audio) is the subject's `seconds`, or the kind's.
- An optional OpenAI-compatible language model (`PromptWriter`) rewrites the subject part only,
  in the style the image model's family reads best (booru tags or prose), once per batch, cached.
  If it can't be reached the batch goes ahead as written, and the recipe says why.

An image recipe: `medium, model, family, loras, positive, negative, width, height, transparent,
parts` and, as a batch adds them, `write, cutout, ground, source, denoise, draft, steps, full,
refines, source_image, workflow, writer_error`. An audio recipe: `medium, model, positive, lyrics,
seconds, parts, workflow`.

## 4. Workflows, built per server

Nothing is templated (`Comfy::Workflow`, `Comfy::Music`). Each graph is built for one candidate
against what that ComfyUI reports installed (`Comfy::Capabilities`, from `/object_info`, one node
at a time), with the fewest nodes that do the job:

- The model loads the way it is stored: a checkpoint in `CheckpointLoaderSimple`; a bare diffusion
  model in `UNETLoader` with its family's text encoder (`CLIPLoader`, the first `type` the server
  offers) and VAE found beside it.
- A model's file name picks its **family** (`families` in `config/comfy.yml`: Anima by default,
  Krea 2, SDXL lineages with Pony/Illustrious/Lightning variants, SD 1.5), which sets loaders,
  steps, CFG, sampler and scheduler preferences, CLIP skip, quality words, negative use and size
  range. An unknown name goes by where the file is.
- LoRAs chain in stack order (`LoraLoaderModelOnly`, or `LoraLoader` where the family's LoRAs
  train the text encoder). No negative encode at CFG 1 (`ConditioningZeroOut`).
- Background removal, when asked, happens in the same workflow: the render is saved, put through
  ComfyUI-RMBG's `BiRefNetRMBG` (`Cutout`), and saved again; the cut-out is mended with libvips
  (`Cutout.keep_interior`) so white inside the subject is kept, having been rendered on a coloured
  ground. Each image is checked for real transparency.
- Audio is ACE-Step through ComfyUI's own nodes, saved as MP3 where the server can, else FLAC.
- **A missing file or node stops the batch before anything is queued**, saying what's missing.
  The studio previews the outline ("UNETLoader → CLIPLoader → …") or the problem before Generate.
- ComfyUI is reached over plain HTTP, with an optional bearer token, headers or basic auth in the
  URL (`Remote::Connection`), so it can be anywhere. Secrets never go in the database or messages.

## 5. Batches, candidates, picks

- **Generate** (`Subjects::BatchesController#create`) first saves the subject layer as written in
  the studio, then `Batch.start!` freezes the recipe and makes 1–8 candidates, each its own seed,
  for the subject, one variant, or every variant (one batch each). A new batch replaces the
  target's previous one.
- `BatchJob` uploads any source image, submits every candidate, then re-enqueues itself every few
  seconds (`ApplicationJob#poll_comfy`) collecting files as they land, without holding a worker,
  until all are in, it fails, or it times out (`timeout`). ComfyUI unreachable means `waiting` and
  retry with back-off for about a day (`waits_for_services`); ComfyUI refusing means `failed`, with
  its reason. Status: `queued → (waiting) → running → done | failed`.
- Each change broadcasts a `reload_frame` Turbo Stream to `[subject, :studio]`; the studio's
  `batches` frame reloads itself, leaving the rest of the page (a half-typed form) alone.
- **Drafts** (images): rough previews (`draft` in config, or Settings), then "Make this one
  properly" (`Batch.refine!`) re-renders one at full size from the draft image, re-noised by
  `draft.denoise`, with the same seed. "Use the draft" picks it as it is.
- **Pick** (`Candidate#pick!`): the file becomes the target's `Pick`, with its seed, prompt,
  recipe and run time; the batch (and its drafts) go.

### Entries and model sheets

- An entry's page is its page in the bible: its lore, its look, and every subject of it, kind by
  kind, with their picks. From it, "Make Cid as…" starts a subject of any kind, of that entry.
- The starter kinds include a **Model sheet**: a character's reference views, each its own
  full-size picture rather than one crowded sheet. The face gets the room (front, both
  three-quarter views, which carry what's on one side only), with a few full-body views (front,
  side, back) for build and clothes. Expressions stay with Portrait. Laying the views out as one
  sheet is the entry page's job, not ComfyUI's.

### Variants and chains

- A variant's batch adds its words last. Its first candidate takes the seed of the subject's own
  pick, when there is one, so a face holds across variants.
- **Starting from a pick** (images): any image pick in the project can be the start of a batch
  (`source: { pick_id, crop, label }`), image to image, re-noised by `denoise`; its first candidate
  takes that pick's seed. `crop: "head"` cuts the head and shoulders square from a full-body figure
  first (`Headshot`). Drafts are off for these.
- polychrome's chain is this, generically: a "Character sprite" subject, then a "Portrait" subject
  started from the sprite's pick with "Only the head" (`chain.head_denoise`, 0.55), then "Generate
  every variant" started from the portrait's own pick (`chain.denoise`, 0.45).

## 6. Settings

`SiteSetting` (one row, the Settings page) overrides `config/comfy.yml` and `config/llm.yml`, which
read the environment: ComfyUI's address, default image and audio models, the background-removal
model, draft size, steps and denoise, candidates per batch, and the language model's address and
model. **Only addresses and names go in the database.** A token, headers or a password stay in the
environment (`COMFY_TOKEN`, `COMFY_HEADERS`, basic auth in `COMFY_URL`, `LLM_TOKEN`, `LLM_HEADERS`),
and a URL with a password in it is refused. `ConnectionCheck` explains, step by step, why ComfyUI
or the language model can't be reached (also `bin/rails services:check`).

## 7. Export

Assets leave baible as files. There is no API.

- `GET /picks/:id/download`: the pick's file, as an attachment (`<subject>[-<variant>]-<seed>.png`,
  or `.mp3`/`.flac`).
- `GET /picks/:id/sidecar`: its sidecar, `<same stem>.json`.
- `GET /projects/:id/manifest`: every current pick in the project, as JSON:
  `{ "baible": 1, "project", "exported_at", "picks": [ <sidecar> + "download_url", "sidecar_url" ] }`.
  No archive (no zip gem): fetch what it lists, signed in.

### The sidecar (version 1)

Every key is always present; what doesn't apply is `null`. `Pick#sidecar`.

| Key | Type | What |
| --- | --- | --- |
| `baible` | integer | The sidecar's format version: `1`. Bumped when a key changes meaning or goes |
| `file` | string | The file's name, as downloaded |
| `content_type` | string | `image/png`, `audio/mpeg`, `audio/flac` |
| `byte_size` | integer | |
| `sha256` | string | Hex digest of the file, to match sidecar to file |
| `medium` | string | `image` or `audio` |
| `project`, `kind`, `subject` | string | Names, where it sits in baible |
| `entry` | string \| null | The entry the subject depicts, or null |
| `variant` | string \| null | The variant's name, or null for the subject itself |
| `seed` | integer | The sampler seed |
| `prompt` | string | The positive prompt as sent (for audio, the tags) |
| `negative` | string \| null | Image only; null when the model takes none |
| `model` | string | The model file as named in the recipe |
| `family` | string \| null | Image only: the family it ran as (`anima`, `sdxl`, …) |
| `loras` | array | The LoRAs that took part, `[{ "name", "strength", "on": true }]` |
| `width`, `height` | integer \| null | Image only: the rendered size |
| `transparent` | boolean \| null | Image only: whether the background was taken off |
| `lyrics` | string \| null | Audio only; null for instrumental |
| `seconds` | integer \| null | Audio only |
| `source` | object \| null | When it started from another pick: `{ "label", "crop"?, "denoise" }` |
| `workflow` | string \| null | The ComfyUI graph's outline, `UNETLoader → CLIPLoader → …` |
| `run_seconds` | number \| null | Seconds ComfyUI spent on it |
| `picked_at` | string | ISO 8601, UTC |
| `recipe` | object | The full recipe (section 3), enough to make it again |

### Into polychrome

polychrome takes uploads only: download the pick (and its sidecar, for the record) and upload the
file in polychrome's own form (a book entry's image, a speaker's portrait or sprite, a track).
polychrome's base world maps onto baible's starter kinds: Creature (Bestiary), Character sprite and
Portrait (speakers; the expressions are Portrait's variants), Item, Emblem (abilities), Location,
Scene (beats), Map, Music. Model sheet has no slot there: it's reference for baible's own use.

## 8. Stack

- Omakase Rails until it is painful not to be. Rails 8.1 defaults: SQLite for everything (Solid
  Queue, Cache and Cable included), Propshaft, importmap, Hotwire, Active Storage on disk. No Node.
- Gems beyond `rails new`: `rspec-rails`, `bcrypt` (the authentication generator),
  `image_processing` (libvips, which `Cutout` and `Headshot` use directly). Nothing else until a
  concrete problem calls for it. HTTP is `Net::HTTP` (`Remote`).
- ComfyUI (with ComfyUI-RMBG for background removal, ACE-Step's checkpoint for audio), anywhere
  over HTTP. Optionally any OpenAI-compatible language model.
- Jobs run in Solid Queue (`bin/jobs`, or `SOLID_QUEUE_IN_PUMA`).

## 9. Conventions

- Controllers only do CRUD. A verb is a resource that hasn't been named yet: generating is
  `Subjects::BatchesController#create`, picking `Candidates::PicksController#create`, making a
  draft properly `Candidates::RefinementsController#create`, downloading
  `Picks::DownloadsController#show`. Nested controllers live in a folder named for their parent and
  load it through a concern (`ProjectScoped`, `SubjectScoped`, `CandidateScoped`, `PickScoped`).
- When the app says no ("only a draft can be made properly"), a model raises `Refusal` and whoever
  asked sees it as an alert. `ArgumentError` means a bug, and crashes.
- A service that can't be reached is waited for (`Remote::Unreachable`); one that answers with an
  error fails the work with its reason. Neither ever shows a secret.
- Recipes are records: once a batch starts, its recipe is frozen; a pick keeps the recipe that made
  it. Editing a layer changes what comes next, never what was made.
- Prefer boring Rails. Stimulus only where a page needs it (`kind-switch`, `flash`); the one custom
  Turbo Stream action is `reload_frame`.
- Specs never reach the network: `FakeComfy`, `FakeHttp`, `ScriptedLlm`. Request specs sign in.
- A migration that removes or changes a column runs outside a transaction
  (`disable_ddl_transaction!`): SQLite rebuilds the table, and inside a transaction it can't switch
  foreign keys off.
