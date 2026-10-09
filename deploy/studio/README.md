# baible on the Studio

How baible runs on the Mac Studio server, in that runbook's conventions: a
container in colima, loopback only, behind Caddy on the tailnet, deployed by
`deploy-apps.sh`. `compose.yaml` and `env.example` beside this are the stack's
files; copy them, don't retype them.

**Verified before this was written:** the image built from this repo and
booted with this `compose.yaml` (on x86-64; `Gemfile.lock` carries
`aarch64-linux`, so arm64 should build too, but that has not been tried).
It was healthy in about 9s, `/health` answered 200 and `/` 302 to
`/session/new`, HSTS and a `secure` session cookie came through, all four
Solid Queue processes registered, a real batch was taken by the worker and
went to `waiting` when it couldn't reach ComfyUI at `host.docker.internal:8188`,
and an Active Storage upload landed in `/rails/files`. **Not verified:** any of
it on the Studio, against the real ComfyUI and llama-swap, through Caddy, or
through a reboot.

## What it is, in the runbook's table

| Item | Value |
| --- | --- |
| Stack | `~/stacks/baible`: `compose.yaml`, `.env`, `app/` (git checkout of `bobbymeyer/baible`, tracking `main`) |
| Image | `baible:current`, built here from source |
| Listens | `127.0.0.1:3006` → container `:80` (Thruster → Puma) |
| Ingress | `https://baible.bobbymeyer.com` via Caddy |
| Data | volume `baible_baible_storage`: four SQLite databases. Volume `baible_baible_files`: Active Storage (every candidate and pick) |
| Secrets | `~/stacks/baible/.env`: `SECRET_KEY_BASE` only, 600, git-ignored |
| Talks to | ComfyUI (`host.docker.internal:8188`) and llama-swap (`host.docker.internal:8090/v1`), both native agents, through `host-gateway` |

## Why it's configured the way it is

- **Port 3006.** 3003 to 3005 are food, polychrome and onbox. 3002 is free
  since the chassis went, and that is the reason not to take it: anything still
  pointing at the chassis would land here and answer instead of failing.
- **Thruster, so the container side is 80**, like funcooker and polychrome and
  unlike onbox. The Dockerfile ends `CMD ["./bin/thrust", ...]` and the
  Gemfile has `thruster`.
- **Solid Queue is on, and it is the whole app.** Every batch and every
  training run is a job that polls ComfyUI and requeues itself every few
  seconds. Without the supervisor, Generate queues a batch that sits at
  `queued` for ever while every probe stays green. `RAILS_MAX_THREADS` is 5
  for the worker's three threads plus the dispatcher and scheduler.
- **The healthcheck is `/health`, not `/` or `/up`.** baible has sign-in, and
  signed out `/` is a 302 that never touches SQLite: the session lookup is
  skipped when there's no cookie. `/up` doesn't touch it either. `/health`
  (HealthController) reads the users table and answers 200 or 503, so it is
  something `deploy-apps.sh` can roll back on.
- **`assume_ssl` and `force_ssl` are both on**, as in polychrome and onbox,
  and they go on together: `assume_ssl` is what lets the plain-HTTP
  healthcheck get 200 instead of a 301.
- **Accounts are made from the console.** There is no sign-up page, so no
  window between the Caddy block going in and an account being claimed.
- **Krea 2 Turbo is the image model** (`COMFY_MODEL`), because it is the one
  the Studio has. baible's Krea 2 settings already match the runbook's:
  8 steps, CFG 1.0, euler/simple, CLIPLoader type `krea2`, at least 1024
  pixels. It runs its text encoder on the CPU, about 80s per new prompt, and
  every candidate in a batch shares one prompt, so that's paid once a batch.
- **Characters train on SDXL**, once it is installed: set
  `COMFY_TRAINING_MODEL` to a full SDXL checkpoint of the lineage the assets
  will be made with (Illustrious, Pony, or base SDXL; their LoRAs don't
  carry to each other). Krea 2 Turbo is distilled and has no LoRA ecosystem;
  the training form says so if it's chosen.
- **`LLM_EXTRA_BODY` turns Qwen3's thinking off**, as funcooker and onbox do.
  With `--reasoning-format deepseek` the thinking goes to a separate field and
  can spend the whole reply, leaving the prompt writer an empty answer. A
  failed rewrite isn't fatal (the batch goes ahead as written and the recipe
  says why), but it would happen every time.
- **`LLM_TIMEOUT` is 600**, for llama-swap's `ttl: 300`: a cold MoE load is
  ~80s alone, and longer when ComfyUI holds the GPU's memory.
- **Overnight runs in Los Angeles time** (`NIGHT_TIME_ZONE`), 23:00 to 07:00 unless the
  Settings page says otherwise. The night shift is a Solid Queue recurring job, so it needs
  nothing on the host: no cron, no launchd. It lets one thing into ComfyUI at a time and only
  when ComfyUI's queue is empty, so it stays out of the way of anything else using ComfyUI
  at night. Training queued for tonight goes after the night's generations.
- **Images live in their own volume** (`ACTIVE_STORAGE_ROOT=/rails/files`).
  See Backups.

## Adding it, in the runbook's order

1. **Merge to `main` first.** `deploy-apps.sh` takes a branch per app, and a
   generated `claude/...` branch name would then live in the script for ever.
2. `mkdir -p ~/stacks/baible && cd ~/stacks/baible`, clone `bobbymeyer/baible`
   into `app/` on `main`, copy `app/deploy/studio/compose.yaml` up one level.
3. Make `.env` without the key touching scrollback:
   `( umask 077; printf 'SECRET_KEY_BASE=%s\n' "$(openssl rand -hex 64)" > .env )`
4. `docker compose up -d --build`, then
   `curl -s -o /dev/null -w "%{http_code}\n" localhost:3006/health` → 200.
5. The account: `docker exec -it -e EMAIL=bobby@... baible ./bin/rails users:create`
   (it asks for the password when `PASSWORD` isn't set).
6. Caddy `handle` block before the catch-all, anchored on `@onbox` the way
   `add-caddy-block.sh` did it; dry-run against a copy, validate, reload (root):

   ```
   	@baible host baible.bobbymeyer.com
   	handle @baible {
   		reverse_proxy localhost:3006
   	}
   ```

7. Netlify A record `baible` → `100.102.129.69`, **before the first lookup**.
8. Verify from a client: `https://baible.bobbymeyer.com/health` → 200 over
   HTTP/2, and a nonsense subdomain still gets the catch-all's 404.
9. Listener audit: nothing new off loopback.
10. Glance: a `monitor` row on `https://baible.bobbymeyer.com/health`,
    expecting 200 (not the bare path: a 302 there proves nothing), and a
    bookmark.
11. `deploy-apps.sh`: `baible|main` in `APPS`. The first poll will rebuild,
    because the image built by hand carries no revision label.
12. `verify-boot.sh`: below.
13. `backup-volumes.sh`: below.

## verify-boot.sh

Drafts in the script's terms; check them against its arrays rather than
pasting blind.

- `PORTS`: `3006`.
- `ENDPOINTS`: `baible`, expecting **302** on the bare path, as the chassis's
  `tools` row did. The deep checks below are what actually prove anything.
- The container is counted from `docker ps`; no edit.
- **A deep check on `/health`**, loopback: `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3006/health` → 200.
- **A deep check on Solid Queue**, from the live table, as onbox's:

  ```bash
  docker exec baible ./bin/rails runner 'puts SolidQueue::Process.order(:kind).pluck(:kind).inspect'
  # want: ["Dispatcher", "Scheduler", "Supervisor(fork)", "Worker"]
  ```

- `backup_targets`: whatever goes into `TARGETS` below, in the same edit.

## Backups

**The databases** (`baible_baible_storage`): SQLite, so the daily stop-and-tar
like funcooker's. Small. Stopping the container mid-batch or mid-training is
safe: the polling job's state is in the queue database, and ComfyUI carries on
regardless.

**The files** (`baible_baible_files`) are the decision. Every candidate is
stored, and pick history keeps every pick, so this volume grows with use and
holds hundreds of MB to GBs of PNGs. Daily archives kept 14 days would be 14
full copies of that. They're in a volume of their own so they can be treated
differently. Options, in the order I'd take them:

1. **An rsync mirror** of the volume to somewhere off this disk, when the
   off-machine destination the runbook still owes is decided. Incremental, so
   it costs one copy.
2. **A weekly archive** kept for two weeks, until then.
3. **Not backed up at all**, on the argument that a pick's sidecar carries
   its full recipe and seed. Weak: the same recipe regenerated on another
   ComfyUI version or with a LoRA changed is not the same picture, and canon
   art is exactly what must not be lost.

Whichever: the databases and the files must be restored as a pair. A
database without its files has picks pointing at nothing; files without their
database are unnamed PNGs.

## ComfyUI side

- **Trained LoRAs land in ComfyUI's output folder** (`SaveLoRA`). Add it to
  the LoRA folders in `~/stacks/comfyui/extra_model_paths.yaml` (the file the
  runbook already uses for `~/comfy-models`), then kickstart ComfyUI:

  ```yaml
  baible:
      base_path: /Users/bobby/stacks/comfyui/output
      loras: loras
  ```

- **Training on this machine is the expensive path.** A run holds ComfyUI's
  queue for hours, shares 64GB with llama-swap and openjev, and runs on MPS.
  The runbook's own rule ("CUDA-dependent or bandwidth-hungry: rent it")
  applies: "Download the set (.tar)" on a run gives a kohya-layout set for a
  rented GPU, and the LoRA it makes goes into `~/comfy-models/loras`. Try
  ComfyUI's own training once, on SDXL, to learn what it costs here.
- **baible writes into ComfyUI's input folder**: chain sources and draft
  refinements as single PNGs, training sets under `input/baible/train/`. It
  never cleans them up. Worth a look after a few training runs.

## Operating

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:3006/health        # 200 = Rails + SQLite
docker exec baible ./bin/rails runner 'puts SolidQueue::Process.order(:kind).pluck(:kind).inspect'
# anything stuck? batches not finished long after they started
docker exec baible ./bin/rails runner 'puts Batch.where(status: %w[queued waiting running]).where("updated_at < ?", 30.minutes.ago).count'
docker exec baible ./bin/rails runner 'puts Training.group(:status).count.inspect'
docker exec baible ./bin/rails services:check                                 # ComfyUI and the language model, step by step
docker compose logs -f baible
```
