# baible — Handoff

A tool for rapidly and consistently making the assets of a world: images and audio, generated in
ComfyUI from layered recipes, picked by a person, and handed on as files. Rails app.

This document is the design contract. Read it before writing code. Where it conflicts with a
shortcut, the document wins until Bobby changes it.

**Status.** Everything here is built. The LoRA loop (section 6), its training hosts, the night
shift (section 7) and the language model's families and workflows (section 4, "Unknown models
and new workflows") are built but not yet tried against a real ComfyUI, a rented GPU or a local
language model; their open questions are listed where they are described.

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
- No API between baible and polychrome (or anything else). Assets leave as files (section 9).
- No asset library or DAM features: tagging, search, collections. Picks keep their history so
  canon and training sets can be chosen from them; that is all. An entry gathers what depicts one
  thing; it is not a folder or a tag.
- No training code of its own. Training runs in ComfyUI's own nodes, built and queued like any
  other workflow (section 6); a set can also leave as files for a trainer elsewhere.
- No inpainting editor, no image editing.
- Not multi-tenant. No per-project permissions, no sign-up page.

## 2. Data model

```
Project ─┬─ Kind ──────────┐            (a kind belongs to a project, and may derive from another)
         ├─ Entry ─────────┤            (an entry belongs to a project; the bible)
         │    ├─ Note                   (a signed note on an entry)
         │    └─ Training               (one LoRA training run, from the entry's picks)
         └─ Subject ───────┴─ Variant   (a subject belongs to a project, one of its kinds and maybe an entry;
                                         it may derive from another subject: Cid's portrait from Cid)
                Subject / Variant ─── Batch ─── Candidate        (rounds of generation)
                Subject / Variant ─── Pick (a history per target: one current, at most one canon)
LearnedFamily / LearnedWorkflow ─── Trial   (Kind ─ LearnedWorkflow, optional)
SiteSetting (one row)   User ─ Session
```

| Model | What | Columns that matter |
| --- | --- | --- |
| `Project` | A world or setting; the top layer | `name` (unique), `description` (never in a prompt), `style`, `negative`, `model`, `loras`, `sound` |
| `Kind` | A kind of asset in a project, named freely ("Creature", "Portrait", "Map", "Theme music"); the middle layer | `medium` (`image` \| `audio` \| `sheet`), `prompt` (the framing), `negative`, `width`, `height`, `transparent`, `model`, `loras`, `seconds`, `variant_presets`, `learned_workflow` (an accepted one, or none for the builder's graph), `parent` (the kind it derives from), `derive` (`words`, `picture`, `head`), `derive_denoise`, `sheet_kind_ids` (section 5) |
| `Entry` | One thing in the world across kinds (Cid; the harbour town); the entry layer, between kind and subject | `name` (unique in its project), `look`, `loras`, `lore` (never in a prompt), `trigger` (for its next LoRA), `training` (the run whose LoRA it uses) |
| `StandingOrder` | Work the night shift plans for itself every night (section 7) | `project`, `kind`, `entry` (both optional), `user`, `action` (`fill_gaps`, `until_canon`, `train`), `count`, `nightly_limit`, `min_pictures`, `model`, `enabled`, `planned_at`, `report` |
| `LearnedFamily` | A family the language model proposed for a model `config/comfy.yml` doesn't know (section 4) | `slug` (unique, `learned-…`), `label`, `model`, `match`, `settings` (as a config family), `status` (`asking`, `proposed`, `accepted`, `failed`), `error`, `log`, `user`, `accepted_by`, `accepted_at` |
| `LearnedWorkflow` | A ComfyUI graph the language model wrote from a description, with placeholders (section 4) | `name` (unique), `purpose`, `graph`, `outline`, and the same status columns |
| `Trial` | A test render of a learned family or workflow | `learnable` (either), `status` (as a batch), `error`, `prompt`, `seed`, `comfy_prompt_id`, `submitted_at`, `run_seconds`, attached `image` |
| `Note` | A note on an entry: a question, a decision, a note to whoever draws it next. Never in a prompt | `entry`, `user` (null once their account goes), `body` |
| `Subject` | The thing made: a goblin, Cid, the harbour town, its theme; the subject layer | `kind`, `entry` (optional), `parent` (the subject it derives from, optional), `name` (unique in its kind), `notes`, `model`, `loras`, `lyrics`, `seconds` |
| `Variant` | A detail layer after a subject ("happy": "smiling happily") | `name` (unique in its subject), `prompt` |
| `Batch` | One round for a **target**: a subject (`variant` nil) or one of its variants; or one queued for the night (section 7) | `recipe` (frozen at start), `status` (`scheduled` for tonight, then `queued` …), `error`, `night`, `released_at`, `submitted_at` |
| `Candidate` | One ComfyUI prompt in a batch, with its own seed, and the file it made | `seed`, `comfy_prompt_id`, `status`, `transparent`, `run_seconds`, attached `file` |
| `Pick` | A chosen file for a target, and how it was made. Kept: a target has a history, one `current` pick and at most one canon pick (section 5) | `seed`, `prompt`, `recipe`, `run_seconds`, `user` (who picked it), `current`, `canon_at`, `canon_by` (a user), attached `file` |
| `SiteSetting` | Where ComfyUI and the language model are, default models, draft tuning, the night window | see sections 7 and 8 |
| `NightSummary` | One night's summary, written when the window closes (section 7) | `opened_at`, `closed_at` (unique), `text`, `payload`, `sent_at`, `error` |
| `Training` | One LoRA training run for an entry, frozen at start like a recipe (section 6); "set" is a set kept without training, "scheduled" one to train tonight (section 7) | `entry`, `user`, `version`, `status` (`set`, `scheduled`, then as a batch), `error`, `trigger`, `model`, `family`, `settings`, `items` (`[{ pick_id, title, seed, sha256, file, caption }]`), `lora` (the name ComfyUI knows it by), attached `lora_file`, `host` (`local`, `remote`), `host_started_at`, `host_note`, `workflow`, `comfy_prompt_id`, `submitted_at`, `run_seconds` |

- A new project starts with the kinds in `config/comfy.yml` (`kinds`) unless asked not to; each is
  editable and removable. A kind with subjects can't be removed or change medium.
- A new subject starts with its kind's `variant_presets` as variants (a portrait's expressions).
- A subject's entry is one of its own project's. Deleting an entry keeps its subjects, unlinked.
- JSON columns hold LoRA stacks (`[{ "name", "strength", "on" }]`, cleaned by `ArtDirection.loras`)
  and recipes.
- Foreign keys are plain; the models clean up (`dependent:`).

## 3. The layered recipe

Everything ComfyUI needs apart from the seed is composed from up to six layers, top to bottom
(`Subject#recipe`, `Subject#layers`):

| Layer | Image | Audio |
| --- | --- | --- |
| Project | `style`, `negative`, `model`, `loras` | `sound` |
| Kind | `prompt` (framing), `negative`, size, `transparent`, `model`, `loras` | `prompt` (tags), `seconds`, `model` |
| Entry, when the subject has one | its LoRA's trigger, `look`; its trained LoRA, `loras` | nothing |
| Parents, when the subject derives from others (section 5), root first | each one's name and `notes`, `model`, `loras` | not derived |
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
- **Parents** (a derived subject's, section 5) come after the entry, as written, never rewritten:
  Cid's words before his costume's, his costume's before the portrait's. A derived subject's own
  layer is its `notes` alone: its name is a label, its parent already names it. Recipes from
  before derived kinds, and subjects that derive from nothing, have no `parent` part.
- **Model:** the lowest layer that names one wins, then the default (`SiteSetting`, then
  `config/comfy.yml`). A derived subject's kind comes before its parents (a sprite kind's pixel-art model beats the
  character's), and they before the project. Audio skips the project (its model is an image model): subject, kind, then
  ACE-Step's checkpoint (`music.model`).
- **LoRAs** (image) stack in layer order, project first (an entry's come after the kind's: a LoRA
  trained on that character, say; then the parents'). A lower layer naming the same LoRA changes
  its strength in place, or switches it off. Switched-off LoRAs stay in the recipe, for the record.
- **Size** (image) is the kind's, scaled into the family's trained range, keeping its shape.
- **Length** (audio) is the subject's `seconds`, or the kind's.
- The language model's requests can carry more fields (`LLM_EXTRA_BODY`): Qwen3 on llama.cpp
  needs its thinking turned off, or it can spend the whole reply.
- An optional OpenAI-compatible language model (`PromptWriter`) rewrites the subject part only,
  in the style the image model's family reads best (booru tags or prose), once per batch, cached.
  If it can't be reached the batch goes ahead as written, and the recipe says why.

An image recipe: `medium, model, family, loras, positive, negative, width, height, transparent,
parts` and, as a batch adds them, `write, cutout, ground, source, denoise, draft, steps, full,
refines, source_image, workflow, writer_error`. An audio recipe: `medium, model, positive, lyrics,
seconds, parts, workflow`. A sheet's: `medium` (`sheet`), `sheet` (`title`, `rows`: `label`,
`subject_id`, `cells`: `pick_id`, `label`), and `width, height` once laid out.

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

### Unknown models and new workflows

Model agnostic is a rule: no model needs a code change. A model whose name no family matches runs
by where its file is, with generic settings, which often works and sometimes doesn't. The
language model (the same optional, OpenAI-compatible one `PromptWriter` uses, local first) closes
that gap on the Models and workflows page (`/learning`, from Settings), as an assistant whose
output is checked, not trusted:

- **A family for an unknown model** (`FamilyWriter`). The page lists every model ComfyUI has and
  how each runs (a config family, a learned one, or unknown: by folder). "Ask the language model"
  on an unknown one gives it the file name and folder, the server's text encoders, CLIP types,
  VAEs, samplers, schedulers and latent nodes, and two config families as examples; it answers
  with a family as `config/comfy.yml` writes one (`LearnedFamily::KEYS`).
- **A workflow the builder can't make** (`WorkflowWriter`), from a name and a description. First
  it is shown every node class on the server and asked which it needs (30 at most); then it is
  given those nodes' full definitions (choices cut to 20) and the builder's own graph for an
  ordinary picture as an example, and writes a graph in API form. Where a batch's values go it
  puts placeholders (`Comfy::Template`): `{{prompt}}`, `{{negative}}`, `{{prefix}}` (strings),
  `{{seed}}`, `{{width}}`, `{{height}}` (integers), `{{model}}`, `{{source_image}}` (files). It
  must save with `SaveImage` and `filename_prefix` `{{prefix}}`.
- **Checked against the server** before anyone sees it: a family by `Comfy::FamilyCheck` (its
  encoder, CLIP type, VAE, sampler and scheduler are on the server; steps, CFG, sizes and styles
  in range), a graph by `Comfy::GraphCheck` (every node class exists, every input is one the node
  takes, links point at real outputs of a compatible type, values are in the node's choices and
  ranges, required inputs are there, placeholders sit where their kind of value goes). A
  proposal that fails is sent back with the problems, three answers at most, then failed with the
  reason; every exchange is kept in the item's `log`, shown on the page.
- **A person tries it, then accepts it.** "Try it" makes a test render (`Trial`, `TrialJob`): a
  family through the builder with its settings, a workflow filled with the default model and a
  test prompt (a workflow that needs `{{source_image}}` can't be tried alone yet). Accept is
  refused until the latest trial is done. A person may edit the settings or graph as JSON; an
  edit is checked the same way and goes back to proposed, to be tried again.
- **Accepted, it is data, reused as is.** An accepted family joins `config/comfy.yml`'s
  (`Comfy::Family.configured`, the config winning a slug clash) and matches its model from then
  on. A kind may make its pictures with an accepted workflow (the kind's page): its graph is
  frozen into each batch's recipe (`recipe["learned_workflow"]`), filled per candidate, and
  checked against the server's definitions of its nodes before anything is queued, so a node or
  file the server no longer has stops the batch, saying so. Such a batch has no drafts and no
  background removal, and starts from a picture only if the graph takes `{{source_image}}`. The
  language model is never asked per batch, so a recipe made with it stays reproducible, and the
  recipe and sidecar carry the graph as for any batch. Deleting a workflow sends its kinds back to
  the builder; later edits don't touch recipes already frozen.
- Without a language model, or when it can't help, everything works as before: the builder, the
  config's families, and the by-folder fallback. The builder stays the first choice wherever it
  can do the job; the fewest nodes still wins.

Open: which local models are good enough at ComfyUI graphs to be worth it, tried on a few models
the config doesn't know; and whether the training graph (section 6) should become a learned
workflow on servers whose trainer nodes differ.

## 5. Batches, candidates, picks

- **Generate** (`Subjects::BatchesController#create`) first saves the subject layer as written in
  the studio, then `Batch.start!` freezes the recipe and makes 1–8 candidates, each its own seed,
  for the subject, one variant, or every variant (one batch each). A new batch replaces the
  target's previous one, except the night's (section 7).
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
  sheet is a sheet kind's job (below), not ComfyUI's.

### Derived kinds and sheets

A character is made once and everything else of it is derived from it: its portraits and their
expressions, its turnaround, its battle sprite, its costumes. baible knows none of those words: it
knows kinds that derive from kinds, subjects that derive from subjects, and sheets.

- **A kind may derive from another** of the project's (`Kind#parent`; a tree, never a loop, and
  only from an image kind). The starter kinds put a **Character** at the top, with Character
  sprite, Portrait, Model sheet and **Costume** derived from it, and a **Character design sheet**.
  Any project can rearrange that on its Kinds page; the rest of the starters stand alone.
- **A subject of a derived kind may derive from a subject** of the kind it derives from, or of a
  kind derived from that (`Subject#parent`, `Kind#parent_kinds`): Cid's portrait from Cid; the
  portrait of Cid's winter coat from that costume, itself from Cid. Never from itself, what derives
  from it, or a sheet. It depicts its parent's entry unless it says otherwise. Its parents' layers
  come before its own (section 3). A subject of a derived kind can still stand alone (an
  unnamed guard's portrait).
- **Where its batches start** is the kind's `derive`: `words` (its layers alone: a back view
  can't be redrawn from a front one), `picture` (redraw the parent's picture), or `head` (the head
  cut from it, `Headshot`), re-noised by `derive_denoise` or `chain` in config/comfy.yml.
  A variant redraws its own subject's picture instead, once it has one: an expression from the
  neutral portrait. This is the default (`Batch.start!` with `source: :derived`; the studio
  preselects it, and it can be changed or turned off per batch), so standing orders and the night
  shift follow it too. Until the parent has a picture, it starts from words. A batch that starts
  from a picture has no drafts.
- **In the studio**, a subject's "Derived from" section lists every kind that can derive from it,
  with what already does; "Make one" (`Subjects::DerivationsController`) adds one named as the
  parent, "Make one of every kind" fills in the rest, and a costume or a second version is added
  with a name of its own from New subject.
- **A sheet** is a kind of medium `sheet`, of a parent kind (required): it makes nothing in
  ComfyUI. Each of its subjects is of one subject (Cid), and "Lay out the sheet" puts what stands
  for each target (canon, else current) of that subject and everything derived from it, of the
  kinds in `sheet_kind_ids` (all, when none are chosen), into one picture (`Sheet`, libvips): a
  title, a row for each subject (labelled with its kind, and its name when that differs), each
  picture 512 pixels high with its label (the kind, or the variant), wrapping at six. The plan
  (`recipe["sheet"]`: the pick ids and labels) is frozen when the batch starts; it is laid out by
  `BatchJob` at once, without ComfyUI, as one candidate, and picked like any other: it has a
  history, canon and a sidecar (`medium: "sheet"`, with the plan in its recipe). A picture gone
  since the plan fails the batch, saying which. A sheet is never a training picture, a chain's
  start, nor a standing order's target. Its labels need a font (the Docker image installs
  `fonts-dejavu-core`); where libvips has none, it is laid out unlabelled.

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

0. **Train characters on SDXL.** Its lineages have LoRA ecosystems and train on its full models.
   Distilled models (Krea 2 Turbo, Lightning-style SDXL) train poorly and are for drafts and looks;
   their family config carries a `training_note` the form shows. `training.model`
   (`COMFY_TRAINING_MODEL`) is the base model a new set offers first, and SDXL has its own
   `training` settings. A set's pictures can come from any model.
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
6. **Where it lands.** `SaveLoRA` writes into the training ComfyUI's *output* folder,
   `output/loras/baible/<stem>_00001_.safetensors`. When the run is done baible fetches it back
   through `/view` (`Training#fetch_lora`, trying the counter up to 5) and keeps it (`lora_file`,
   "Download the LoRA" on the run). When `TRAINED_LORA_DIR` is one of this ComfyUI's LoRA folders
   mounted into baible (config/comfy.yml `trained_loras`), baible writes it there as
   `<stem>.safetensors`, and ComfyUI knows it as `<prefix>/<stem>.safetensors`
   (`TRAINED_LORA_PREFIX`, `baible`). Without that folder, a run trained here goes by its name in
   ComfyUI's outputs (listed once `output/loras` is one of its LoRA folders,
   `extra_model_paths.yaml`), and one trained elsewhere by the name it would have once put in
   `loras/baible`; the entry's page says when ComfyUI can't see it yet, with the download.
7. **Using it.** When a run is done the entry uses it (`Entry#training`; "Use this LoRA" and "Stop
   using it" switch between runs). In an image recipe of its subjects the entry layer then starts
   with the run's trigger and its LoRA leads the entry's LoRAs at 1.0 (`Entry#trained_lora`). A
   LoRA belongs to the **pool** of the model it was trained on (`Comfy::Family#lora_pool`): base
   SDXL, Pony and Illustrious are one family but three pools, since the lineages retrained the
   text encoder and a LoRA from one makes garbage on another, not an error. In a recipe whose
   model is outside its pool it is kept, switched off, and the trigger is left out. A subject can change its strength by naming
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

## 7. Overnight

The machine is idle at night and its owner is asleep: baible uses the time to make what can be
made unattended, for review in the morning (`NightShift`, `NightShiftJob`, `NightsController`).

- **The night window** is `night` in config/comfy.yml (23:00 to 07:00, `NIGHT_TIME_ZONE`), and the
  Settings page overrides it. It may cross midnight.
- **Queueing.** "Queue for tonight" (or every variant) in a studio makes the same batch as
  Generate, recipe frozen then, but as `scheduled` and `night`: no job yet, no drafts (nobody is
  there to choose one; it renders at full quality), and **it replaces nothing and nothing replaces
  it** but a pick or a discard: a morning's Generate replaces the target's daytime batch only, so
  the night's work survives until it is reviewed. "Train tonight" on a training set, or on a kept
  or failed run, makes it `scheduled`.
- **The night shift** (`NightShiftJob`, every minute under Solid Queue, `config/recurring.yml`;
  `bin/rails night:tick` by hand) lets **one** thing go at a time, and only when: the window is
  open, nothing of baible's is queued, waiting or running with ComfyUI, and ComfyUI's own queue
  is empty (`Comfy::Client#queue_size`; it may be busy with work from elsewhere). Generations go
  first, oldest first; then training runs, which take hours. One at a time means whatever someone
  starts by hand at night is never behind the whole queue. Nothing new starts after the window
  closes; what is running finishes. A released batch counts its time with ComfyUI from its
  release (`released_at`), not from the afternoon it was queued.
- **Overnight** (the page, in the masthead with how much is queued): tonight's queue, with "Not
  tonight" to take a batch or run off it, and what the night made: its batches still waiting for a
  pick (the studio's strips, Use this included), and training runs that finished or failed in the
  last day.

### Training hosts

A second ComfyUI to train on (`training_host` in config/comfy.yml: `TRAINING_COMFY_URL`, with
`TRAINING_COMFY_TOKEN` and `TRAINING_COMFY_HEADERS` in the environment only): a rented GPU, or a
GPU box on the tailnet. This ComfyUI then goes on generating while it trains.

- A run is made for one host (`Training#host`, `local` or `remote`) and keeps it: the training host
  by default when one is set, else here; the training form offers both. Its job talks to that
  ComfyUI (`Comfy.client_for`) with the same graph, uploads and polling as a local run. The host
  needs ComfyUI's training nodes and the base model under the same file name. A remote run whose
  host has since gone from the configuration fails with that reason.
- **RunPod**, when `RUNPOD_API_KEY` (environment only) and `training_host.runpod_pod_id`
  (`RUNPOD_POD_ID`) are set: the pod is started before the run (`POST
  rest.runpod.io/v1/pods/{id}/start`, `RunPod.start!`) and stopped after it, done or failed
  (`/stop`), so it costs only while it trains. A stopped pod keeps its volume, so ComfyUI, its
  nodes and the base models stay on it between runs. For `training_host.boot_minutes` (20) after
  the start, a ComfyUI that isn't up yet (RunPod's proxy answering 502) is waited for rather than
  failed. RunPod refusing (a wrong key or pod) fails the run with its reason. **A pod that wouldn't
  stop is said loudly**: `host_note` on the run, its page, and the first line of the morning summary
  ("NEEDS YOU"), since it costs money until someone stops it.
- **The night shift** gives the host its own track: a scheduled remote run goes as soon as the host
  has nothing of baible's, without waiting for this ComfyUI's generations, which don't wait for it.
  One run at a time on the host.
- The pod's ComfyUI is unauthenticated behind RunPod's proxy address, which is the only thing
  keeping it private: the same posture as ComfyUI on the tailnet, on a machine someone else owns.
  baible stops it when it isn't training; keep nothing on it you'd mind losing.
- Open, to settle against RunPod: how long a stopped pod takes to bring ComfyUI back (the boot
  window), what an SDXL character LoRA costs there, and whether uploading a set through the proxy is
  reliable.

### The morning summary

At the first tick after the window closes, the night shift writes one summary of that night
(`NightSummary.write!`, once per night by `closed_at`; `Window#last_night` says which night): the
batches made, failed and still going with the candidate count, what waits for review by project,
failures, training runs that ended or are still going, how much was not reached, each standing
order's report, and a link to the Overnight page (`APP_URL`). The figures are kept too (`payload`).

- It is kept and shown at the top of the Overnight page, with the six mornings before it.
- **It is sent** when `MORNING_WEBHOOK_URL` is set (environment only: a webhook's address is often
  its secret): as JSON with a `text` field and the figures beside it (`MORNING_WEBHOOK_FORMAT`
  `json`, the default: n8n, Slack, Mattermost), or as plain text (`text`: ntfy).
  `MORNING_WEBHOOK_HEADERS` adds headers as JSON (a token, ntfy's `Title`). A send that fails is
  kept with its reason on the page and not retried: a summary of last night that turns up at noon
  is worth less than knowing it didn't arrive.
- A night that ran nothing still gets a summary ("Nothing ran last night."). Silence and "nothing
  happened" must not look the same.

### Standing orders

Work the night shift plans for itself (`StandingOrder`), kept under "Every night" on the
Overnight page. Each belongs to a project, may be narrowed to one kind and/or one entry, can be
switched off, and does one thing:

| Action | Every night |
| --- | --- |
| Fill the gaps | a batch (`count` candidates) for every target in scope with no pick |
| Keep going until canon | a batch for every target in scope with picks but none approved |
| Train when ready (needs an entry) | a training run, once the entry has `min_pictures` canon image picks and they aren't exactly what its last run trained on; on the order's `model`, else `training.model`; captions from each pick's recipe (`Training.caption_for`); never while its last run is still scheduled or training |

- **Planned once a night**, at the first tick after the window opens (`NightShift.plan!`; each
  order keeps `planned_at`), so its batches are frozen from the layers as they are that night and
  queue after whatever was queued by hand. Then the night shift lets them go like any other.
- **Unreviewed work doesn't pile up.** A target that still has a night batch (queued, made and not
  picked from, or failed and not discarded) gets nothing new, and an order queues at most
  `nightly_limit` batches a night.
- **What it did** is kept as one line (`report`) beside it: "Queued 3 batches of 4; 1 target still
  waiting for review of an earlier night's", "Waiting for 12 canon pictures; Cid has 7", "No base
  model to train on". That line is the morning's answer to "why didn't it make anything?".
- Deleting a project, kind or entry deletes its orders.

## 8. Settings

`SiteSetting` (one row, the Settings page) overrides `config/comfy.yml` and `config/llm.yml`, which
read the environment: ComfyUI's address, default image and audio models, the background-removal
model, draft size, steps and denoise, candidates per batch, and the language model's address and
model. **Only addresses and names go in the database.** A token, headers or a password stay in the
environment (`COMFY_TOKEN`, `COMFY_HEADERS`, basic auth in `COMFY_URL`, `LLM_TOKEN`, `LLM_HEADERS`),
and a URL with a password in it is refused. `ConnectionCheck` explains, step by step, why ComfyUI
or the language model can't be reached (also `bin/rails services:check`).

## 9. Export

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
| `medium` | string | `image`, `audio`, or `sheet` (several picks laid out as one image; the recipe lists them) |
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

## 10. Stack

- Omakase Rails until it is painful not to be. Rails 8.1 defaults: SQLite for everything (Solid
  Queue, Cache and Cable included), Propshaft, importmap, Hotwire, Active Storage on disk. No Node.
- Production keeps its four SQLite databases in `storage/` and Active Storage's files where
  `ACTIVE_STORAGE_ROOT` says (a volume of their own), so the small databases can be archived often
  and the growing image library on its own terms. `GET /health` (HealthController) reads the users
  table, signed out, and is what a healthcheck or deploy gate should probe: `/up` and the
  signed-out redirect never touch the database. `deploy/studio/` is the Studio's stack.
- Gems beyond `rails new`: `rspec-rails`, `bcrypt` (the authentication generator),
  `image_processing` (libvips, which `Cutout` and `Headshot` use directly). Nothing else until a
  concrete problem calls for it. HTTP is `Net::HTTP` (`Remote`).
- ComfyUI (with ComfyUI-RMBG for background removal, ACE-Step's checkpoint for audio), anywhere
  over HTTP. Optionally any OpenAI-compatible language model.
- Jobs run in Solid Queue (`bin/jobs`, or `SOLID_QUEUE_IN_PUMA`).

## 11. Conventions

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
