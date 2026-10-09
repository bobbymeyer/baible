# baible — Handoff

A tool for rapidly and consistently making the assets of a world: images and audio, generated in
ComfyUI from layered recipes, picked by a person, and handed on as files. Rails app.

This document is the design contract. Read it before writing code. Where it conflicts with a
shortcut, the document wins until Bobby changes it.

**Status.** Everything here is built except what is marked **Planned**: the language model's part
in running unknown models and building workflows (section 4, "Unknown models and new
workflows"). The LoRA loop (section 6) is built but not yet tried against a real ComfyUI; its
open questions are listed there.

## 1. What it is

- A workshop for one person or a small team. Everyone signed in sees every project.
- A **project** is a world or a setting. Its house style is the first layer of everything made in it.
- An **entry** is one thing in that world across every kind it's made in: Cid, whose sprite,
  portrait and key art are each a subject of a different kind. The entries are the project's
  bible: each has lore for people and a look that every image of it carries.
- Every asset is made the same way: a **recipe** composed in layers, a **batch** of candidates in
  ComfyUI (each its own seed), and a **pick**. The pick keeps how it was made, exactly.
- **The loop is the point.** Words alone don't hold a character's face across kinds, poses and
  media. So for anything that must look the same everywhere, baible makes *examples* (the entry's
  look, a model sheet, expressions, a few kinds), a person keeps the good ones, ComfyUI trains a
  LoRA on them, and that LoRA then makes the assets. Its output can feed the next version. The
  entry's look and the model sheet are where this starts, not where it ends.
- Images (any ComfyUI image model the app can recognise, see "Workflows") and audio (ACE-Step).
- **Model agnostic.** baible works with whatever models the user's ComfyUI has, not a list it
  ships with. What it knows about a model is data (a family), never code, and an optional local
  language model helps it learn models and workflows it doesn't know yet (section 4).
- It came out of polychrome, a JRPG tabletop app, whose asset pipeline it is. polychrome is still
  its first customer: it makes polychrome's art and music. Both projects keep their own scope.

### Non-goals

- Not a game, and no knowledge of any game. baible has no idea what a monster, a book or a beat
  is; polychrome's kinds are just kinds a project can have.
- No API between baible and polychrome (or anything else). Assets leave as files (section 8).
- No asset library or DAM features: tagging, search, collections. Picks keep their history so
  canon and training sets can be chosen from them; that is all. An entry gathers what depicts one
  thing; it is not a folder or a tag.
- No training code of its own. Training runs in ComfyUI's own nodes, built and queued like any
  other workflow (section 6); a set can also leave as files for a trainer elsewhere.
- No inpainting editor, no image editing.
- Not multi-tenant. No per-project permissions, no sign-up page.

## 2. Data model

```
Project ─┬─ Kind ──────────┐            (a kind belongs to a project)
         ├─ Entry ─────────┤            (an entry belongs to a project; the bible)
         │    ├─ Note                   (a signed note on an entry)
         │    └─ Training               (one LoRA training run, from the entry's picks)
         └─ Subject ───────┴─ Variant   (a subject belongs to a project, one of its kinds and maybe an entry)
                Subject / Variant ─── Batch ─── Candidate        (rounds of generation)
                Subject / Variant ─── Pick (a history per target: one current, at most one canon)
SiteSetting (one row)   User ─ Session
```

| Model | What | Columns that matter |
| --- | --- | --- |
| `Project` | A world or setting; the top layer | `name` (unique), `description` (never in a prompt), `style`, `negative`, `model`, `loras`, `sound` |
| `Kind` | A kind of asset in a project, named freely ("Creature", "Portrait", "Map", "Theme music"); the middle layer | `medium` (`image` \| `audio`), `prompt` (the framing), `negative`, `width`, `height`, `transparent`, `model`, `loras`, `seconds`, `variant_presets` |
| `Entry` | One thing in the world across kinds (Cid; the harbour town); the entry layer, between kind and subject | `name` (unique in its project), `look`, `loras`, `lore` (never in a prompt), `trigger` (for its next LoRA), `training` (the run whose LoRA it uses) |
| `Note` | A note on an entry: a question, a decision, a note to whoever draws it next. Never in a prompt | `entry`, `user` (null once their account goes), `body` |
| `Subject` | The thing made: a goblin, Cid, the harbour town, its theme; the subject layer | `kind`, `entry` (optional), `name` (unique in its kind), `notes`, `model`, `loras`, `lyrics`, `seconds` |
| `Variant` | A detail layer after a subject ("happy": "smiling happily") | `name` (unique in its subject), `prompt` |
| `Batch` | One round for a **target**: a subject (`variant` nil) or one of its variants | `recipe` (frozen at start), `status`, `error`, `submitted_at` |
| `Candidate` | One ComfyUI prompt in a batch, with its own seed, and the file it made | `seed`, `comfy_prompt_id`, `status`, `transparent`, `run_seconds`, attached `file` |
| `Pick` | A chosen file for a target, and how it was made. Kept: a target has a history, one `current` pick and at most one canon pick (section 5) | `seed`, `prompt`, `recipe`, `run_seconds`, `user` (who picked it), `current`, `canon_at`, `canon_by` (a user), attached `file` |
| `SiteSetting` | Where ComfyUI and the language model are, default models, draft tuning | see section 7 |
| `Training` | One LoRA training run for an entry, frozen at start like a recipe (section 6); "set" is a set kept without training | `entry`, `user`, `version`, `status` (`set`, then as a batch), `error`, `trigger`, `model`, `family`, `settings`, `items` (`[{ pick_id, title, seed, sha256, file, caption }]`), `lora` (the file), `workflow`, `comfy_prompt_id`, `submitted_at`, `run_seconds` |

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
| Entry, when the subject has one | its LoRA's trigger, `look`; its trained LoRA, `loras` | nothing |
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

### Unknown models and new workflows (Planned)

Model agnostic is a rule: no model needs a code change. Today a model whose name no family
matches runs by where its file is, with generic settings, which often works and sometimes
doesn't. The language model (the same optional, OpenAI-compatible one `PromptWriter` uses, local
first) is to close that gap, as an assistant whose output is checked, not trusted:

- **A family for an unknown model.** Given the model's file name and where it sits, and what the
  server reports (`/object_info`: loaders, text encoders, VAEs, samplers), it proposes a family
  entry: how the model loads, its text encoder and VAE, steps, CFG, sampler and scheduler, CLIP
  skip, quality and negative words, prompt style (tags or prose) and size range.
- **A workflow the builder can't make.** For what `Comfy::Workflow` doesn't build (a new
  architecture, ControlNet or pose-sheet graphs, the training graph in section 6), it proposes a
  ComfyUI graph in API form, with the inputs baible fills in (prompt, seed, size, files) named.
- **Checked against the server**, node by node, before anyone sees it: every node class exists,
  every input is one that node takes with a value it accepts, every file is on the server. A
  proposal that fails is sent back with what failed, a few times at most, then dropped with the
  reason.
- **A person accepts it**, seeing the outline and a test render. Accepted, it is saved as data
  (a family in the database beside `config/comfy.yml`'s, or a stored workflow) and reused as is:
  the language model is never asked per batch, so a recipe made with it stays reproducible, and
  the recipe and sidecar record the graph as for any batch.
- Without a language model, or when it can't help, everything works as now: the builder, the
  config's families, and the by-folder fallback. The builder stays the first choice wherever it
  can do the job; the fewest nodes still wins.

Open: which local models are good enough at ComfyUI graphs to be worth it, tried on a few models
the config doesn't know.

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
- **Pick** (`Candidate#pick!`): the file becomes a new `Pick` of the target, its current one,
  with its seed, prompt, recipe, run time and who picked it; the batch (and its drafts) go.

### Picks: history and canon

Picks are kept: approved art must not be lost to a later pick, and a training set needs more than
one picture per target.

- **Picking keeps.** A new pick becomes the target's **current** pick (`Pick.adopt!`); the one
  before stays in the target's history, file and recipe intact, and "Use this again"
  (`Picks::CurrentsController`) makes it current again. One current pick per target, held by a
  partial unique index.
- **Canon** is a deliberate mark, at most one per target (also a partial unique index): "Approve as
  canon" (`Picks::CanonsController`, `Pick#approve!`) records who and when, and takes canon from
  any other pick of the target; "Unapprove" takes it back.
  A canon pick is not replaced by picking: the new pick becomes current, canon stays, and the
  studio shows both until someone approves the new one. Canon never blocks generating; exploring
  is cheap, overwriting what was approved is not.
- What stands for a target (`Subject#pick_for`, `Pick.standing`) is its canon pick, or its current
  one when nothing is canon: on the studio and entry pages, the project page, the manifest, the
  picks a chain can start from, and a variant's seed hint. The studio shows it marked Canon or
  Current, says when a newer pick waits for approval, and lists the whole history under it.
- **Let go** (`Pick#let_go!`) removes one pick, file and all. It is refused (`Refusal`) on a canon
  pick until that is unapproved, and on a pick a training run used (section 6), since that run's
  record would point at nothing. When the current pick goes, the newest left becomes current.
- Who picked and approved is kept as a user; when that account goes, the pick stays, unsigned.

### Entries and model sheets

- An entry's page is its page in the bible: its lore, its look, and every subject of it, kind by
  kind, with their picks. From it, "Make Cid as…" starts a subject of any kind, of that entry.
- **Notes** on an entry are a log, newest first, each signed with its author's account and time.
  Anyone signed in adds one; only its author takes it back (`Entries::NotesController`). They are
  for people: like lore, never in a prompt, and not in the sidecar.
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

## 6. The LoRA loop

For an entry that must look the same everywhere: examples, a person's choice, a LoRA, then
assets made with it. baible curates and records; ComfyUI trains (`Training`, `TrainingJob`,
`Comfy::Training`).

1. **Examples.** The entry's look gives a first, word-level consistency; the Model sheet (front,
   both three-quarter views, full-body views), Portrait expressions and a few other kinds give the
   variety a LoRA needs: everything varies except identity. Chains (section 5) help hold the face
   while making them. A couple of dozen good images is the usual order of size; quality over count.
2. **The set** ("New training set" on the entry's page, `Entries::TrainingsController#new`): every
   image pick of every subject of the entry, history included, each target's standing pick ticked.
   Audio never joins.
3. **Captions** (`Training.caption_for`), one per picture, from its pick's recipe: the house style,
   the framing, the subject (as the language model wrote it, if it did) and the detail, but **not
   the entry's look** (that is what the LoRA should learn to tie to the trigger) and not the
   family's quality words. Editable in the form. The run puts the **trigger** first in each: the
   entry's `trigger`, or its name as a word (`Entry#trigger_or_default`); the one given is kept as
   the entry's for next time.
4. **Kept or trained.** "Only keep the set" makes a `Training` in status `set`; "Train in ComfyUI"
   (red: it spends ComfyUI's time, for hours) also queues it, and so does training a kept or
   failed one later (`Trainings::RunsController`). A run is frozen when made: its pictures (pick,
   title, seed, sha256, file name), captions, trigger, base model and family, and settings
   (`steps`, `rank`, `learning_rate`, `batch_size`: config/comfy.yml `training`, a family's own
   `training` over it, then the form's). Versions count up per entry.
5. **The run** (`TrainingJob`, polled like a batch through `ComfyRun`, with `training.timeout`,
   six hours by default). It uploads each picture, **flattened on white** (`Cutout.on_white`:
   ComfyUI's dataset loader drops alpha, and a cut-out's hidden pixels are no background to
   learn), with its caption beside it as a `.txt`, into `input/baible/train/<stem>/` (`/upload/image`
   stores what it's sent), then queues the graph built for that server: the base model loaded as
   for a picture (`Comfy::Workflow.load`) → `LoadImageTextDataSetFromFolder` →
   `MakeTrainingDataset` → `ResolutionBucket` (pictures of different shapes) → `TrainLoraNode`
   (`bucket_mode` on; inputs baible doesn't set take the defaults ComfyUI reports) → `SaveLoRA`
   (prefix `loras/baible/<stem>`). `<stem>` is project, entry and version:
   `the-drowned-coast-cid-v1`. A missing node stops it before anything is queued, as for a batch.
   It is done when ComfyUI's history says so, failed with ComfyUI's reason when it errors.
6. **Where it lands.** `SaveLoRA` writes into ComfyUI's *output* folder,
   `output/loras/baible/<stem>_00001_.safetensors`. ComfyUI lists it once that folder is one of
   its LoRA folders (`extra_model_paths.yaml`, README "Training"), as `baible/<stem>_00001_.safetensors`;
   until then the entry's page says so. A file moved into `models/loras` is found by its name.
7. **Using it.** When a run is done the entry uses it (`Entry#training`; "Use this LoRA" and "Stop
   using it" switch between runs). In an image recipe of its subjects the entry layer then starts
   with the run's trigger and its LoRA leads the entry's LoRAs at 1.0 (`Entry#trained_lora`). A
   LoRA belongs to the family it was trained on: in a recipe whose model is of another family it
   is kept, switched off, and the trigger is left out. A subject can change its strength by naming
   it in its own LoRAs. The look stays; shorten it to what the LoRA gets wrong.
8. **Again.** Picks made with v1 can go into v2's set. Every run stays on the entry's page with its
   set, captions, settings, result and error; deleting one is refused while ComfyUI has it, and
   leaves the LoRA file on ComfyUI.
9. **Elsewhere.** Every run, kept or trained, downloads as a `.tar` (`Trainings::SetsController`,
   Ruby's own `Gem::Package::TarWriter`) in the kohya layout: `<stem>/1_<trigger>/001.png` with
   `001.txt` beside it, for a trainer outside ComfyUI. A LoRA trained anywhere is a file in
   ComfyUI's LoRAs, and goes on the entry's LoRAs like any other.

ComfyUI runs one prompt at a time: batches queued behind a run wait for it.

Open, to settle against a real server: which families ComfyUI's training nodes take (Anima in
particular), whether a folder made by upload just before queueing passes `LoadImageTextDataSetFromFolder`'s
folder check, sensible settings per family, and what a run costs in time and memory on the GPU
baible will use.

## 7. Settings

`SiteSetting` (one row, the Settings page) overrides `config/comfy.yml` and `config/llm.yml`, which
read the environment: ComfyUI's address, default image and audio models, the background-removal
model, draft size, steps and denoise, candidates per batch, and the language model's address and
model. **Only addresses and names go in the database.** A token, headers or a password stay in the
environment (`COMFY_TOKEN`, `COMFY_HEADERS`, basic auth in `COMFY_URL`, `LLM_TOKEN`, `LLM_HEADERS`),
and a URL with a password in it is refused. `ConnectionCheck` explains, step by step, why ComfyUI
or the language model can't be reached (also `bin/rails services:check`).

## 8. Export

Assets leave baible as files. There is no API.

- `GET /picks/:id/download`: the pick's file, as an attachment (`<subject>[-<variant>]-<seed>.png`,
  or `.mp3`/`.flac`).
- `GET /picks/:id/sidecar`: its sidecar, `<same stem>.json`.
- `GET /projects/:id/manifest`: the pick that stands for each target in the project (its canon,
  else its current pick), as JSON:
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
| `picked_by` | string \| null | The email address of whoever picked it; null when unknown or gone |
| `canon` | boolean | Whether it is its target's canon pick |
| `canon_by`, `canon_at` | string \| null | Who approved it as canon, and when (ISO 8601, UTC) |
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
| `picked_at` | string | When it was picked, ISO 8601, UTC |
| `recipe` | object | The full recipe (section 3), enough to make it again |

### Into polychrome

polychrome takes uploads only: download the pick (and its sidecar, for the record) and upload the
file in polychrome's own form (a book entry's image, a speaker's portrait or sprite, a track).
polychrome's base world maps onto baible's starter kinds: Creature (Bestiary), Character sprite and
Portrait (speakers; the expressions are Portrait's variants), Item, Emblem (abilities), Location,
Scene (beats), Map, Music. Model sheet has no slot there: it's reference for baible's own use.

## 9. Stack

- Omakase Rails until it is painful not to be. Rails 8.1 defaults: SQLite for everything (Solid
  Queue, Cache and Cable included), Propshaft, importmap, Hotwire, Active Storage on disk. No Node.
- Gems beyond `rails new`: `rspec-rails`, `bcrypt` (the authentication generator),
  `image_processing` (libvips, which `Cutout` and `Headshot` use directly). Nothing else until a
  concrete problem calls for it. HTTP is `Net::HTTP` (`Remote`).
- ComfyUI (with ComfyUI-RMBG for background removal, ACE-Step's checkpoint for audio), anywhere
  over HTTP. Optionally any OpenAI-compatible language model.
- Jobs run in Solid Queue (`bin/jobs`, or `SOLID_QUEUE_IN_PUMA`).

## 10. Conventions

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
