# Third-Party Notices

The components listed below are not owned by the OpenPigeon project. They are
not covered by [LICENSE](LICENSE) or [LICENSE-ASSETS](LICENSE-ASSETS), and
retain their original terms.

---

## Not distributed with this repository

**Player.IO Android SDK** - `app/libs/PlayerIO.aar`

Proprietary. The Player.IO Terms of Service prohibit redistribution of their
software, so the binary is not included in this repository.

Used only by Crazy 8 multiplayer. All other games build and run without it.

To build Crazy 8 multiplayer, obtain the SDK yourself from
<https://playerio.com> and place it at `app/libs/PlayerIO.aar`. You will need
your own Player.IO account; accounts are not transferable. See
[CONTRIBUTING.md](CONTRIBUTING.md).

---

## Engine and libraries

**Godot Engine** - MIT License
<https://godotengine.org/license>

**godot-box2d** - MIT License
`app/src/main/assets/addons/godot-box2d/`
See `LICENSE.txt` and `THIRDPARTY.txt` in that directory. Those files must not
be removed.

**Box2D** - MIT License
`app/src/main/cpp/box2d` (git submodule)

**Android Game Development Kit (Swappy frame pacing)** - Apache License 2.0
`app/src/main/java/com/google/androidgamesdk/`
<https://android.googlesource.com/platform/frameworks/opt/gamesdk/+/refs/heads/main/games-frame-pacing/extras/>

`ChoreographerCallback.java` and `SwappyDisplayManager.java` are vendored
verbatim from AGDK. Godot statically links Swappy's native half and looks these
classes up by name; shipping them keeps Swappy off its in-memory DEX fallback,
which hardened Android builds block. See the header comments in those files.

---

## Creative Commons assets

Attribution required. These may be redistributed under their own terms and are
excluded from LICENSE-ASSETS.

**Sky Backdrop** - bart - CC-BY 3.0
<https://opengameart.org/content/sky-backdrop>
`app/src/main/assets/archery/sky1.png`

**Basket Ball Texture** - Downdate - CC-BY 3.0
<https://opengameart.org/content/basket-ball-texture>
`app/src/main/assets/basketball/balldimpled.png`

**Arrow** - Boy Best - CC-BY 4.0
<https://sketchfab.com/3d-models/arrow-c46f8feb96044a95967feee111488e03>
`app/src/main/assets/archery/arrow/`

Attribution is also displayed in-app via
`app/src/main/assets/attributions.html`.

---

## Sound effects

The following sound effects are third-party works and retain their original
licenses. They are excluded from LICENSE-ASSETS.

| Sound | Creator | Source | License |
|---|---|---|---|
| Golf Swing | jcampbe8 | https://freesound.org/s/638884/ | CC0 1.0 |
| Basketball Bounce (`basket_ball_02_bounce.wav`) | andre.nascimento | https://freesound.org/s/51461/ | CC BY 4.0 |
| `golf_hole.wav` | inbeeld | https://freesound.org/s/21878/ | CC0 1.0 |
| Golf ball - single bounce - `golf_bounce.wav` | 221098HariPotter | https://freesound.org/s/655635/ | CC BY 4.0 |
| `pool_pocket.wav` | Yarmonics | https://freesound.org/s/441857/ | CC0 1.0 |
| Pool Ball Strike | ChloePieterse | https://freesound.org/s/763603/ | CC0 1.0 |
| `Pool_Table_Ball_Hit.WAV` | AmberdeMeillon | https://freesound.org/s/443067/ | CC0 1.0 |

Attribution is also displayed in-app via
`app/src/main/assets/attributions.html`.

---

## Fonts

Fonts are excluded from LICENSE-ASSETS and remain under their own terms. OFL
fonts must retain their copyright notices and Reserved Font Names, and cannot
be relicensed.

| Font | File | License |
|---|---|---|
| Inter | `app/src/main/res/font/inter_variable.ttf` | SIL OFL 1.1 |
| Lexend | `app/src/main/res/font/lexend_medium.ttf`, `lexend_variable.ttf` | SIL OFL 1.1 |
| Fivo Sans | `app/src/main/res/font/fivosans_black.otf`, `fivosans_bold.otf`, `fivosans_heavy.otf` | SIL OFL 1.1 |
| Jellee | `app/src/main/res/font/jellee_roman.ttf` | SIL OFL 1.1 |
| DSEG | `app/src/main/assets/basketball/dseg7_classic_bold.ttf` | SIL OFL 1.1 |

License texts: `app/src/main/res/raw/ofl_*.txt` and
`app/src/main/assets/basketball/OFL-DSEG.txt`.

All fonts are under the SIL Open Font License 1.1. Their copyright notices and
Reserved Font Names must be retained, and they cannot be relicensed under
LICENSE-ASSETS. Full license texts accompany the font files.

---

## Original work

The following are original work of the OpenPigeon project and are **not**
third-party components:

- Word lists - `app/src/main/assets/global/dictionaries/op_wg_*.txt`,
  `app/src/main/res/raw/op_wg_*.txt`, `app/src/main/res/raw/gp_en2.txt`.
  Authored by the project. Covered by LICENSE.
- All artwork, audio, and 3D models not listed above. Covered by
  LICENSE-ASSETS.
