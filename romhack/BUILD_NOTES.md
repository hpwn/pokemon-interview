# pokeemerald-expansion Migration Notes

## Compiler Requirements

- **devkitARM r64 or newer**: required for the modern build path and the expanded engine features.
- **arm-none-eabi-gcc 12.x**: tested with the toolchain bundled in devkitARM r64.
- Ensure `pip install -r romhack/pokeemerald/requirements.txt` has been executed prior to building tools.

## Migration Fixes

- Applied upstream `MODERN` build path defaults in `make` to align with the expansion repository.
- Updated overrides to match the new field move and scripting APIs introduced in the expansion fork.
- Resolved script compilation errors by regenerating the poryscript outputs against the new constants set.
- Verified event data compatibility after expanding the NPC mailbox script.

## Recommended Build Steps

1. From the repository root, initialize submodules:
   ```bash
   git submodule update --init --recursive
   ```
2. Apply local overrides:
   ```bash
   ./romhack/apply_overrides.sh
   ```
3. Build tools and the ROM:
   ```bash
   cd romhack/pokeemerald
   make clean
   make tools -j
   make MODERN=1 -j
   ```

ROM output: `romhack/pokeemerald/pokeemerald.gba`
