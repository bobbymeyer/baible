# baible

A tool for rapidly and consistently building the assets of a world: images and audio, generated in
[ComfyUI](https://github.com/comfyanonymous/ComfyUI) from layered recipes, picked by a person, and
handed on as files with a JSON sidecar saying exactly how each was made. It makes polychrome's art
and music, and anyone else's.

The design contract is [docs/HANDOFF.md](docs/HANDOFF.md); the look is [docs/DESIGN.md](docs/DESIGN.md).

## Setup

You need Ruby 3.3 (`.ruby-version`), SQLite and libvips (`apt install libvips sqlite3`, or
`brew install vips`). No Node.

```sh
bin/setup --skip-server          # gems, the databases (SQLite, in storage/), clears logs
bin/rails users:create           # asks for an email and a password (10 characters or more)
bin/dev                          # the app on http://localhost:3000
```

- **Accounts.** There's no sign-up page: everyone with an account sees every project. Make one with
  `bin/rails users:create`, or `EMAIL=me@example.com PASSWORD=… bin/rails users:create` (the same
  task resets a password), or `EMAIL=… PASSWORD=… bin/rails db:seed`. From the console:
  `User.create!(email_address: "me@example.com", password: "…")`.
- **Jobs** drive generation. In development they run inside the server (Active Job's async
  adapter), so `bin/dev` is all you need. In production they run in Solid Queue: the Dockerfile sets
  `SOLID_QUEUE_IN_PUMA=1` so Puma runs the worker; unset it and run `bin/jobs` to keep them apart.
- **Password reset emails** need Action Mailer configured (SMTP and a `from` address in
  `ApplicationMailer`); until then use `bin/rails users:create`.
- **Tests:** `bin/rspec`. Lint: `bin/rubocop`. Security: `bin/brakeman`. All of it: `bin/ci`.

## Pointing it at ComfyUI

ComfyUI can be anywhere the app reaches over HTTP: the same machine, the LAN, a tailnet, behind a
proxy. Set its address on the **Settings** page or in the environment; the page's "Check the
connection" (or `bin/rails services:check`) walks each step (address, name, port, answer) and says
what a failure usually means.

| Variable | Default | What |
| --- | --- | --- |
| `COMFY_URL` | `http://127.0.0.1:8188` | Where ComfyUI answers. A path prefix and `https://user:pass@host` basic auth both work |
| `COMFY_TOKEN` | blank | Sent as `Authorization: Bearer …` |
| `COMFY_HEADERS` | `{}` | Other headers a proxy wants, as JSON (Cloudflare Access's, say) |
| `COMFY_MODEL` | `anima-preview.safetensors` | The image model when no layer names one |
| `COMFY_MUSIC_MODEL` | `ace_step_v1_3.5b.safetensors` | ACE-Step's checkpoint when no audio layer names one |
| `COMFY_RMBG_MODEL` | `BiRefNet_toonout` | The model ComfyUI-RMBG takes backgrounds off with |
| `COMFY_RMBG_GROUND` | `green` | The colour cut-out pictures are rendered on in place of white; blank keeps white |
| `LLM_URL` | blank (off) | An OpenAI-compatible API, up to `/v1` (llama.cpp, llama-swap, Ollama, LM Studio, vLLM, hosted) |
| `LLM_MODEL` | blank | The model to ask for, as the server names it |
| `LLM_TOKEN`, `LLM_HEADERS` | blank | As for ComfyUI |
| `LLM_TIMEOUT` | `120` | Seconds, room for the server to load the model |

The Settings page overrides the addresses and model names. Tokens, headers and passwords only ever
live in the environment, never in the database, and no message repeats them.

### What ComfyUI needs

- **An image model.** Anima by default: `anima-preview.safetensors` in `models/diffusion_models`,
  `qwen_3_06b_base.safetensors` in `models/text_encoders`, `qwen_image_vae.safetensors` in
  `models/vae` (Comfy Org's repackaged release; bf16 files on Apple Silicon). Any checkpoint works
  too; the pickers list what ComfyUI has, models grouped by the family they'd run as and LoRAs by
  subfolder.
- **Background removal:** [ComfyUI-RMBG](https://github.com/1038lab/ComfyUI-RMBG) (by 1038lab,
  from the Manager), **version 3.1.0** (3.2.0 doesn't load without triton, as on a Mac). It fetches
  its model into `models/RMBG` the first time.
- **Audio:** ComfyUI 0.3.34 or later, and ACE-Step's checkpoint in `models/checkpoints`.
- From a container, ComfyUI on the host is usually `http://host.docker.internal:8188` (run the
  container with `--add-host=host.docker.internal:host-gateway`, and ComfyUI with `--listen`).
  ComfyUI also keeps everything it makes in `output/baible/`.

### config/comfy.yml

How each family of model runs (`families`: loaders, text encoder and VAE files, steps, CFG,
samplers, CLIP skip, quality words, size range), draft and chain tuning, background removal, ACE-Step
settings, and the `kinds` a new project starts with. A model's file name picks its family; add a
`match` to teach it a new name, or a family for a new architecture that loads the same way.
`config/llm.yml` holds the language model's.

## Using it

1. **Make a project** (a world): its house style, negative prompt, model and LoRAs for images, and
   its sound for audio. It starts with the usual kinds unless you untick that.
2. **Kinds** (the project's art direction): framing, negative, size, background removal, model and
   LoRAs per kind of image; tags, length and checkpoint per kind of audio; and the variants each new
   subject starts with (a Portrait's expressions).
3. **Add a subject** to a kind: the goblin, Cid, the harbour town, the harbour's theme.
4. **In its studio**, see the layers, write its notes (and model and LoRAs, or lyrics and length),
   and **Generate** for the subject, one variant, or every variant. Drafts first by default for
   images: "Make this one properly" renders the one you like at full quality from the draft.
   Candidates appear as they land, for everyone watching.
5. **Use this** picks a candidate: it becomes the subject's (or variant's) pick, with its seed and
   recipe.
6. **Chains:** a batch can start from any image pick in the project, the whole picture or only the
   head cut from a full-body figure. Sprite, then a portrait from its head, then every expression
   from the portrait: the same face throughout.

Every pick has **Download** (the file) and **Sidecar** (how it was made, as JSON; the schema is in
HANDOFF "Export"). The project's **Manifest** lists every current pick with where to download each.

## Bringing assets into polychrome

polychrome only takes uploads; there's no API between the two.

1. In baible, pick the asset, then **Download** it (and the **Sidecar**, if you want the record).
2. In polychrome, open the thing it's for and upload the file in its form: a book entry's image on
   its edit page, a speaker's portraits (one per expression) and sprite in their form, a track in
   the world's Music book.

The starter kinds line up with polychrome's slots: Creature (Bestiary), Item (Armory), Emblem
(Grimoire), Location (Gazetteer), Character sprite and Portrait (speakers; Portrait's variants are
polychrome's expressions, the subject itself being Neutral), Scene (scene panels), Map, Music.

## Layout

| Path | What |
| --- | --- |
| `app/models/project.rb`, `kind.rb`, `subject.rb`, `variant.rb` | The layers; `Subject#recipe` composes them |
| `app/models/batch.rb`, `candidate.rb`, `pick.rb`, `app/jobs/batch_job.rb` | Generating, collecting, picking; `Pick#sidecar` |
| `app/models/comfy/`, `remote.rb`, `llm/`, `prompt_writer.rb` | ComfyUI and the language model over HTTP, workflow building |
| `app/models/cutout.rb`, `headshot.rb` | Background removal and its mending; the head cut for chains |
| `app/models/site_setting.rb`, `connection_check.rb` | Settings and the step-by-step connection check |
| `app/controllers/subjects/`, `candidates/`, `picks/`, `projects/` | Nested resources (verbs as resources) |
| `spec/support/fake_comfy.rb` | A ComfyUI stand-in for specs |
