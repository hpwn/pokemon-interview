# Pokémon Interview Trainer (MVP)

Turn Pokémon (pokeemerald-expansion) into an interview trainer via an emulator–AI bridge.

## Architecture

- **ROM (pokeemerald-expansion + Poryscript)**: an NPC sets a "mailbox" in RAM and shows "Connecting...".
- **Lua (BizHawk or mGBA)**: watches RAM, calls local FastAPI, writes reply back into RAM.
- **FastAPI server**: serves prompts, hints, and a simple keyword rubric.

## Quick start (expansion)

1. Submodule: `pokeemerald-expansion` (already wired). Apply overrides:
   ```bash
   ./romhack/apply_overrides.sh
   ```

2. Build tools then ROM (WSL/Ubuntu):

   ```bash
   cd romhack/pokeemerald-expansion
   make clean
   make tools -j
   make MODERN=1 -j
   ```

   ROM: `romhack/pokeemerald-expansion/pokeemerald.gba`
3. API:

   ```bash
   ./scripts/dev-up.sh
   ```
4. Emulator: BizHawk → load ROM → Tools → Lua Console → open `bridge/bizhawk_ai_bridge.lua`.

   * Press **K** to inject a test request.
   * Dialog appears for MCQ/TF/Short/Code → answer → in-game mailbox gets response.

## Notes

* Don’t distribute ROMs. Ship IPS/UPS patches + scripts only.

* If mGBA Lua lacks HTTP, switch to a tiny Python sidecar that reads/writes memory via the emulator's scripting or a TCP socket.

## Why the expansion fork?

`pokeemerald-expansion` adds the modernized build system, decomps for later-generation features, and scripting quality-of-life patches from rh-hideout. Those updates unlock:

- Modern compiler support via the `MODERN=1` toolchain.
- More robust event scripting suited for AI-driven NPC logic.
- Easier integration points for future generative AI experiments.
