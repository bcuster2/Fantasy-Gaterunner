# Credits & Asset Licenses

Every third-party asset in this project is listed here with its license. Only CC0 or
free-for-commercial-use assets are allowed.

| Asset | Source | License | Used for |
|---|---|---|---|
| Godot Engine 4.7 | https://godotengine.org | MIT | Engine |
| Default project font (Open Sans, bundled with Godot) | https://godotengine.org | OFL 1.1 (bundled with engine) | UI and 3D text |

## Original / generated content

- 3D models: built in code from primitive meshes (`core/visuals/placeholders.gd`). Original, no license required.
- Sound effects and music (`assets/audio/**/*.wav`): original. They're rendered offline by our own synthesizer
  (`tools/audio_forge.gd`): 28 sound effects, plus music loops for forest, crypt, volcano, boss, and menu.
  No samples or third-party audio are used. A tiny runtime synth (`autoload/audio_manager.gd`) remains as a
  fallback.
- Particle, shockwave, lightning, and coin effects: original, code-built (`core/fx/`).

## Replacing audio with third-party CC0 packs

Copy the files into `assets/audio/`, point the sound ids at them in `data/sounds.json`, and add a row to
the table above (asset, source URL, license). Kenney.nl audio packs are CC0. Their site blocks automated
downloads, so fetch them by hand.
- Shaders: original (`core/shaders/`).
- Element icons (`assets/icons/*.svg`): original, hand-written SVG.
