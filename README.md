# Pokémon Interview Trainer (MVP)

Turn Pokémon (pokeemerald) into an interview trainer via an emulator–AI bridge.

## Architecture

- **ROM (pokeemerald + Poryscript)**: an NPC sets a "mailbox" in RAM and shows "Connecting...".
- **Lua (BizHawk or mGBA)**: watches RAM, calls local FastAPI, writes reply back into RAM.
- **FastAPI server**: serves prompts, hints, and a simple keyword rubric.

## Quick start

1. Build `pokeemerald` normally (see upstream README). Put `data/scripts/ai_trainer.pory` into your scripts and include it.
2. Pick a mailbox region in EWRAM (default stub: `0x03005C00`) and/or expose `VAR_AI_*` addresses. Update the Lua file accordingly.
3. Start API:
   ```bash
   cd server
   python -m venv .venv && . .venv/bin/activate
   pip install -r requirements.txt
   uvicorn app:app --reload
````

4. Run emulator (BizHawk recommended for LuaSocket), load your built ROM, then run `bridge/mgba_ai_bridge.lua`.
5. Talk to the AI Trainer NPC in-game.

## Notes

* Don’t distribute ROMs. Ship IPS/UPS patches + scripts only.
* If mGBA Lua lacks HTTP, switch to a tiny Python sidecar that reads/writes memory via the emulator's scripting or a TCP socket.