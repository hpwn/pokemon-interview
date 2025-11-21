# Pokémon Interview Trainer (MVP)

Turn Pokémon (pokeemerald-expansion) into an interview trainer via an emulator–AI bridge.

## Architecture

- **ROM (pokeemerald-expansion + Poryscript)**: an NPC sets a "mailbox" in RAM and shows "Connecting...".
- **Lua (BizHawk or mGBA)**: watches RAM, calls local FastAPI, writes reply back into RAM. See the `bridge/` directory for emulator-side scripts.
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

   After building with `MODERN=1` you’ll get **pokeemerald.gba** (expansion keeps the same filename; the build mode is reflected in the map/compile flags).
3. API:

   ```bash
   ./scripts/dev-up.sh
   ```
4. Emulator: BizHawk → load ROM → Tools → Lua Console → open `bridge/bizhawk_ai_bridge.lua`.

   * BizHawk 2.11+ currently exposes no HTTP client inside its Lua sandbox, so API calls will log `API error -1 (No HTTP client available)` until you provide one externally.
   * Use `bridge/bizhawk_mailbox_test.lua` to inject a single test packet into the mailbox.

## Notes

* Don’t distribute ROMs. Ship IPS/UPS patches + scripts only.

* If mGBA Lua lacks HTTP, switch to a tiny Python sidecar that reads/writes memory via the emulator's scripting or a TCP socket.

## BizHawk test flow

1. Build the ROM and start the FastAPI server (`./scripts/dev-up.sh`).
2. In BizHawk: load `pokeemerald.gba`, open Tools → Lua Console, and load `bridge/bizhawk_ai_bridge.lua`.
3. In the same Lua Console, run `bridge/bizhawk_mailbox_test.lua` to write a test packet at the mailbox address (`0x03005C00`).
4. Observe the Lua Console logs. Because BizHawk lacks an HTTP client, the bridge reports `API error -1 (No HTTP client available)` while still demonstrating the mailbox read/write loop.

## Why the expansion fork?

`pokeemerald-expansion` adds the modernized build system, decomps for later-generation features, and scripting quality-of-life patches from rh-hideout. Those updates unlock:

- Modern compiler support via the `MODERN=1` toolchain.
- More robust event scripting suited for AI-driven NPC logic.
- Easier integration points for future generative AI experiments.
