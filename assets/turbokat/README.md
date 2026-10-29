# Custom TurboKat model (optional)

Put a glTF binary here as `turbokat.glb` and the game uses it in place of the
procedural airframe in `scripts/player/turbokat_model.gd`. Without it, the procedural
model is used.

1. On the model's Sketchfab page, check the **license** shown under the title.
   - CC-BY / CC-BY-SA / CC0: fine to commit. Add the credit line below (CC-BY requires it).
   - "Standard" / "Editorial" / not downloadable: **do not commit it** to this public repo.
     Keep it local (it's covered by `.gitignore` until you remove that line) or skip it.
2. Download → **glTF** (or "Autoconverted format (glb)"), and save it as `turbokat.glb`.
3. Open the project in Godot once (or run `godot --headless --path . --import`) so it is imported.
4. Tune the constants at the top of `turbokat_model.gd` if needed:
   `CUSTOM_ROTATION_DEG` (nose must point to -Z), `CUSTOM_LENGTH`, `CUSTOM_NOZZLES`.
   Check it with: `xvfb-run godot --path . --rendering-driver opengl3 -- --showcase=/tmp/shots`

## Credits

<!-- e.g. "SWAT Cat TurboKat plane" by <author> (https://sketchfab.com/...) licensed under CC-BY 4.0 -->
