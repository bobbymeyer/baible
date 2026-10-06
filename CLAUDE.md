# CLAUDE.md

- `docs/HANDOFF.md` is the design contract. Read it before writing code. Where a shortcut conflicts with it, the document wins.
- `docs/DESIGN.md` is the visual starting point: Swiss, after polychrome's, with black grotesk type on white, geometry for state, grey controls and red for Generate. Diverge where the work needs it, and record each divergence in that document.
- baible makes assets (images and audio) in ComfyUI from layered recipes. It knows nothing about any game, polychrome included: assets leave as files with a JSON sidecar (HANDOFF "Export").
- The ComfyUI library (`Comfy::*`, `Remote`, `Llm`, `PromptWriter`, `Cutout`, `Headshot`, `ConnectionCheck`) is ported from polychrome and battle-tested. Change it only when the data model needs it, and keep its specs green.
- Run the tests with `bin/rspec`. Specs never reach a real ComfyUI or language model: use `FakeComfy`, `FakeHttp` and `ScriptedLlm` (spec/support).
- Omakase Rails until it is painful not to be (HANDOFF "Stack"). Use SQLite and the Rails 8 defaults, and add no gems or infrastructure until a concrete problem calls for it.
