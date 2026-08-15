# Contributing to OpenPigeon

We're actively looking for game developers to contribute.

Before you start, read the [License section of the README](README.md#license).
OpenPigeon is source-available, not open source, and the terms differ from what
you may expect. In particular, artwork and audio cannot be redistributed.

## Contribution terms

By submitting a pull request, patch, or any other contribution to OpenPigeon,
you agree that:

- Your contribution is your original work, or you have the right to submit it
- You grant the OpenPigeon project a perpetual, worldwide, irrevocable,
  royalty-free license to use, modify, distribute, sublicense, and relicense
  your contribution, under the project's current terms and any future terms the
  project adopts
- You retain copyright in your own work
- Your contribution includes no third-party code, assets, fonts, artwork, or
  audio unless you have identified it and its license in the contribution, and
  you have the right to submit it under those terms

No signature is required. Opening a pull request constitutes agreement.

If you're unsure whether something is allowed, ask: **support@openbubbles.app**.

---

## Building

### Requirements

- Android Studio (recent stable)
- Android NDK and CMake 3.22.1
- Latest Stable Godot Release

### Setup

1. Clone with submodules:

       git clone --recurse-submodules https://github.com/OpenBubbles/OpenPigeon.git

   If you already cloned without them:

       git submodule update --init --recursive

2. Obtain the Player.IO keys:
    - Register a free account at <https://playerio.com>
    - Create a game, and note its game ID and shared secret for step 3

   This is required only for Crazy 8 multiplayer. Every other game runs without
   it, but the build will not proceed until the file is present.

3. Copy `config.properties.example` to `config.properties` in the repository
   root and fill in your own Player.IO credentials:

       PIO_GAME_ID=your-game-id
       PIO_SHARED_SECRET=your-shared-secret

   Both come from your Player.IO dashboard. This file is gitignored so do not
   commit it. The build fails with an explanatory message if it is missing or if
   either value is blank.

4. Point Gradle to your Godot binary. Add `godot.path` to `local.properties` (found under Gradle Scripts in Android Studio):

   - **Windows:** `godot.path=C:\\path\\to\\godot.exe` *(Note: Use double backslashes `\\`)*
   - **macOS:** `godot.path=/Applications/Godot.app/Contents/MacOS/Godot`

   Restart Android Studio after updating `local.properties`.

5. Open `app/src/main/assets` in the Godot editor once, so the import cache is
   generated.

6. In Godot, navigate to **Editor → Editor Settings → Search for ADB → Disable Shutdown ADB on Exit**. This allows the project to correctly build to the phone.

7. Build and install from Android Studio.

### Testing in OpenBubbles

1. Enable developer mode in OpenBubbles → Developer Tools
2. Add the service name: `com.openbubbles.openpigeon.MadridExtensionService`

Contact us on Discord if you want guidance getting set up.

---

## Do not commit

- `config.properties` (credentials)
- `app/libs/*.aar` (proprietary, not redistributable)
- `.idea/`, `.kotlin/`, build output, debug traces

If you add a third-party asset, font, or library, add it to
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) and, where attribution is
required, to `app/src/main/assets/attributions.html` in the same pull request.
Contributions containing assets you do not have the right to license to the
project cannot be merged.
