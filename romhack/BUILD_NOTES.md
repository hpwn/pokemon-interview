# pokeemerald-expansion Build Notes

These notes track the migration from the vanilla `pokeemerald` base to `rh-hideout/pokeemerald-expansion` and outline what is required to build the ROM with the modern toolchain.

## Migration checkpoints

- The submodule now lives at `romhack/pokeemerald-expansion`.
- `./romhack/apply_overrides.sh` copies local assets into that directory.
- Builds target the `MODERN=1` make path; make sure to invoke `make clean` the first time you switch bases.

## Submodule bootstrap

```bash
git submodule update --init --recursive
./romhack/apply_overrides.sh
```

Re-run the override script whenever files under `romhack/overrides/` change.

## Toolchain requirements (Ubuntu 22.04)

`pokeemerald-expansion` expects a modern ARM GCC that matches the upstream project. The setup below is known to work:

```bash
sudo apt update
sudo apt install build-essential git python3 python3-venv libpng-dev gcc-arm-none-eabi binutils-arm-none-eabi
arm-none-eabi-gcc --version  # should report GCC >= 12 for MODERN builds
```

If you use devkitPro, ensure `devkitARM` is on your `PATH` and that `DEVKITPRO`/`DEVKITARM` environment variables are exported before invoking `make`.

## Build commands

```bash
cd romhack/pokeemerald-expansion
make clean
make tools -j$(nproc)
make MODERN=1 -j$(nproc)
```

The finished ROM is written to `romhack/pokeemerald-expansion/pokeemerald.gba`.

## Known gotchas

- `make tools` must be run at least once after cloning or whenever the submodule is updated.
- If you see `No rule to make target 'src/megadata.o'`, the repository may be on an outdated commit; run `git submodule update --remote` to match the pinned version.
- Use `MODERN=0` only if you have the legacy devkitARM toolchain; the interview trainer assumes modern features are available.
