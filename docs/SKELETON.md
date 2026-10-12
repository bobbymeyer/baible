# baible design skeletons: a spec for exporters

This is for someone writing an **exporter**: code in another project (a game, a comic's script
tool, polychrome) that writes the list of art and audio it needs as one JSON file, a
**skeleton**, for [baible](../README.md) to import. baible makes a placeholder for each asset,
generates them, and gives the files back with your own ids attached.

The format is version **1**. [`skeleton.example.json`](skeleton.example.json) is a complete,
working example, and baible's specs import it. Inside baible, any project's own skeleton (its
**Skeleton** page, `GET /projects/:id/skeleton`) is written in the same format.

## The round trip

1. **Your project writes a skeleton**: what it needs (characters, portraits, creatures, places,
   music), each asset with your own id for it, its `ref`.
2. **Someone imports it in baible** (Projects → **Import a skeleton**, a file upload or paste).
   Each asset becomes a placeholder: a subject with nothing picked yet.
3. **baible makes them**: someone generates and picks in the studio, or a standing order fills the
   gaps overnight.
4. **Your project reads the files back** from baible's project **manifest** (JSON, below). Every
   picked file carries your `ref`, and the manifest lists the refs still `missing`.
5. **Export again whenever your needs change.** Re-importing only adds what's new. Nothing is made
   twice, and nothing edited in baible is overwritten.

There is no API in either direction: a JSON file goes in, and files with JSON sidecars come out.

## The file

UTF-8 JSON, one object, at most 5 MB.

```json
{
  "baible_skeleton": 1,
  "source": "polychrome",
  "project": { … },
  "starter_kinds": true,
  "kinds": [ … ],
  "entries": [ … ],
  "assets": [ … ]
}
```

| Key | Type | Required | What |
| --- | --- | --- | --- |
| `baible_skeleton` | integer | **yes** | The format version: `1`. A file without it, or with another number, is refused. |
| `source` | string | no | Who wrote it ("polychrome"). A note for people; baible doesn't act on it. |
| `project` | object | for a new project | The project to import into (below). |
| `starter_kinds` | boolean | no | Default `true`. A **new** project starts with baible's starter kinds (below) unless this is `false`. |
| `kinds` | array | no | Kinds to make, if the project hasn't one of that name (below). |
| `entries` | array | no | Entries in the project's bible: the characters, places and things that recur (below). |
| `assets` | array | no | What you need: one per asset (below). This is the point of the file. |

Unknown keys are ignored, so an exporter can add its own (prefix them, e.g. `"x_polychrome_world"`,
to stay clear of future versions).

### `project`

| Key | Type | What |
| --- | --- | --- |
| `name` | string | **Required for a new project.** baible imports into the project of this name, made if it's new, unless the person imports from inside a project page, which wins. |
| `description` | string | For people; never in a prompt. |
| `style` | string | The house style, the first words of every image prompt ("ink wash, muted sea colours"). |
| `negative` | string | Words to avoid in every image ("text, watermark"). |
| `sound` | string | The house sound: tags that lead every audio prompt ("sea shanty, accordion"). |

Fields only fill blanks: a project that already has a style keeps its own.

### `kinds`

A **kind** is a kind of asset ("Portrait", "Creature", "Theme music"): the framing, size and
medium every asset of it shares. Most exporters don't need any; the starter kinds below cover
common needs. Define one when nothing fits. A kind the project already has, by name, is left as it
is.

| Key | Type | What |
| --- | --- | --- |
| `name` | string | **Required.** Unique in the project. |
| `medium` | string | `image` (default), `audio`, or `sheet` (a picture laid out from other assets' picks, below). |
| `prompt` | string | The framing, after the house style: "a single figure, full body, facing the viewer, plain white background". For audio, tags. |
| `negative` | string | Image only. |
| `width`, `height` | integer | Image only, 256–2048. Default 1024 × 1024. baible scales them into the model's range, keeping the shape. |
| `transparent` | boolean | Image only: take the background off. Default `false`. |
| `seconds` | integer | Audio only, 10–240. Default 60. |
| `from` | string | The name of the kind this one **derives** from ("Character"). It must be a kind the project has, or one earlier in this array. See "Deriving" below. |
| `derive` | string | For a derived kind: how its assets start from their parent's picture. `words` (default: words only), `picture` (redraw the parent's picture), `head` (redraw the head cut from it), or `reference` (draw from the parent's picture in a new pose). A redraw keeps the picture's pose and composition, so use `picture` or `head` only where that is wanted (a portrait from the head, a costume in the same stance). For a new pose (a battle sprite, an action shot) use `reference` on an SDXL or SD 1.5 model with IP-Adapter in ComfyUI, else `words`. |
| `derive_weight` | number | For `reference`, 0.1–1.5: how closely it holds the parent's design. Leave it out for baible's default (0.8). |
| `derive_denoise` | number | 0.1–1.0: how far a redraw strays from the picture it starts from. Leave it out for baible's default. |
| `sheet_of` | array of strings | For a `sheet`: the names of the kinds it lays out. Leave it out for all kinds derived from its `from`. |
| `variants` | object | Variants every new asset of this kind starts with, `{ "name": "words it adds" }`: a portrait's expressions, a sprite's poses. |

### `entries`

An **entry** is one recurring thing in the world (Cid; the harbour town) across every kind of
asset made of it. Its `look` goes word for word into every image of it, which keeps a character
recognisable. Assets name their entry (below). Entries are matched by name; fields only fill
blanks.

| Key | Type | What |
| --- | --- | --- |
| `name` | string | **Required.** Unique in the project. |
| `look` | string | What stays true in every picture of it: face, build, marks, the clothes it's known by. Short and visual. |
| `lore` | string | For people; never in a prompt. |

An asset can name an entry that isn't in this array; it's made with just its name.

### `assets`

One per thing you need. Each becomes a **subject** in baible: a placeholder until something is
picked for it.

| Key | Type | Required | What |
| --- | --- | --- | --- |
| `ref` | string | strongly recommended | **Your** id for this asset. It must be unique in the file and stable across exports. baible keeps it and gives it back with every file made for it. Without a ref the asset is matched by kind and name, and the file comes back unlabelled. |
| `kind` | string | **yes** | The name of a kind the project has (a starter kind, say) or one this file defines. |
| `name` | string | **yes** | What it is: "Cid", "Drowned sailor". Unique within its kind. For an image it leads the prompt (except when the asset derives from another, below). |
| `entry` | string | no | The name of the entry it depicts; the entry's look goes into its prompt. A derived asset takes its parent's entry when it names none. |
| `from` | string or object | no | The asset it **derives** from: that asset's `ref`, or `{ "kind": "…", "name": "…" }`. It can be anywhere in the file, or already in baible. See "Deriving". |
| `notes` | string | no | What it looks like, specifically: "barnacled, a broken lantern". For audio, tags: "slow, swaying, accordion". Keep it visual and short; baible adds the style and framing. |
| `lyrics` | string | no | Audio only. Blank for instrumental. ACE-Step's tags work: `[verse]`, `[chorus]`. |
| `seconds` | integer | no | Audio only, 10–240; else the kind's length. |
| `variants` | array | no | Versions of it that are needed too: `[{ "name", "prompt", "ref" }]`, or `{ "name": "words" }`. A portrait's "happy", a sprite's "attack". Each gets its own file. `prompt` is the words it adds; leave it out to use the kind's preset of the same name. `ref` is your id for that one file. |

## Deriving

Kinds can derive from kinds, and assets from assets: a character first, then its portrait, sprite,
turnaround and costumes, each drawn from the character. A derived asset takes its parent's
words, LoRAs and entry, and (as its kind says) may start from the parent's picture. A redraw
(`picture`, `head`) keeps its pose and composition: right for a portrait cut from the head, wrong
for a new pose. `reference` draws from the picture in a new pose instead (IP-Adapter, on SDXL and
SD 1.5). The entry's `look` and, once trained, its LoRA hold the design too.

- An asset with `from` must be of a kind that derives from the parent's kind (or from a kind
  derived from that): a Portrait can derive from a Character, or from a Costume derived from that
  Character, but not from a Creature.
- A derived asset's `notes` describe only what's different. Its `name` is a label, since the parent
  already names it in the prompt.
- A costume is an asset of its own (`"kind": "Costume", "name": "Cid, winter coat", "from":
  "speaker/12"`), and can have its own portrait (`"from": "speaker/12/winter"`).

## The starter kinds

A new project starts with these (unless `starter_kinds` is `false`), so an exporter can just name
them:

| Kind | Medium | Derives from | Starts from the parent's | Preset variants |
| --- | --- | --- | --- | --- |
| Character | image | — | — | — |
| Character sprite | image | Character | words | — |
| Portrait | image | Character | head | happy, sad, angry, surprised, worried, determined |
| Model sheet | image | Character | words | front, three-quarter left, three-quarter right, full body front, full body side, full body back |
| Costume | image | Character | picture | — |
| Character design sheet | sheet | Character | — | — |
| Creature | image | — | — | — |
| Item | image | — | — | — |
| Emblem | image | — | — | — |
| Location | image | — | — | — |
| Scene | image | — | — | — |
| Map | image | — | — | — |
| Music | audio | — | — | — |

Someone may have renamed or removed kinds in an existing baible project; an asset naming a kind
that isn't there stops the import (below).

## Importing again

Write the whole list every time; baible works out what's new.

- An asset is matched by `ref`, else by `kind` and `name`. A match isn't made again. Its blank
  fields (notes, entry, a ref it lacked, lyrics, length) are filled, but anything a person changed in
  baible stays as it is, even a different name.
- New variants are added to matched assets; existing ones keep their words.
- An asset that drops out of the file is **not** deleted. The import says how many assets with refs
  weren't in this file.
- A matched asset that already derives from something keeps that parent.

So refs must be stable. If one changes, baible sees a new asset.

## Errors

An import is all or nothing. If anything is wrong, nothing is imported, and the page lists every
problem with its place in the file, as `assets[3] (Cid): …`:

- not JSON, not an object, or `baible_skeleton` isn't `1`
- no `project.name` for a new project
- a kind without a name, a `from` naming no kind the project has or none earlier in `kinds`, or
  values out of range
- an asset that isn't an object, lacks a name, or names a kind that isn't there
- a `ref` used twice in the file
- a `from` that's no asset, in the file or in baible
- a parent its kind can't derive from

## What comes back

baible's **manifest** for the project (`GET /projects/:id/manifest`, downloaded signed in, from the
project page) is JSON:

```json
{
  "baible": 1,
  "project": "The Drowned Coast",
  "exported_at": "2026-10-12T09:00:00Z",
  "picks": [
    {
      "ref": "speaker/12/portrait/happy",
      "subject_ref": "speaker/12/portrait",
      "kind": "Portrait", "subject": "Cid", "variant": "happy", "entry": "Cid",
      "file": "cid-happy-123456.png", "content_type": "image/png", "sha256": "…",
      "canon": true,
      "download_url": "https://…/picks/41/download",
      "sidecar_url": "https://…/picks/41/sidecar",
      "…": "every other sidecar key"
    }
  ],
  "missing": [
    { "ref": "bestiary/3", "subject_ref": "bestiary/3", "kind": "Creature", "entry": null, "subject": "Drowned sailor", "variant": null }
  ]
}
```

- `picks` has one file per target that has one: an asset itself (`variant` null) or one of its
  variants. It's the approved (`canon: true`) pick when there is one, else the latest.
- `ref` is your ref for **that file**: the variant's ref, or the asset's for the asset itself.
  `subject_ref` is always the asset's ref. A variant you didn't give a ref (a kind's preset) has
  `ref: null`; match it by `subject_ref` and `variant`.
- `missing` is every target with nothing picked yet.
- Download with the URLs while signed in. Each file's sidecar (`sidecar_url`, the same JSON as its
  entry in `picks`) records exactly how it was made: prompt, model, seed, size and source.
- Images are PNG; audio is MP3, or FLAC where ComfyUI can't write MP3. A `sheet` asset comes back as
  one PNG.

## Checklist for an exporter

- [ ] `"baible_skeleton": 1` at the top, and `project.name`.
- [ ] Every asset has a stable, unique `ref`: your table's id plus a role works well
      (`speaker/12/portrait`).
- [ ] Every asset names a `kind` that exists: a starter kind, or one defined in `kinds`.
- [ ] Characters are a `Character` asset, with their portraits, sprites and costumes deriving from
      it by `from`, and an `entry` with a short `look`.
- [ ] Each variant you need as its own file has its own `ref`.
- [ ] `notes` say what to draw, briefly; no style, framing or quality words, which baible adds.
- [ ] Import [`skeleton.example.json`](skeleton.example.json) once to see what baible makes of a file.
