# Integrating with OpenPigeon

This document is for developers of messaging applications who want their users
to be able to play OpenPigeon games.

**You do not need a license from us to integrate.** OpenPigeon is installed by
the user as a separate application. Your app never bundles or redistributes
OpenPigeon, so nothing in [LICENSE](LICENSE) or [LICENSE-ASSETS](LICENSE-ASSETS)
restricts what you are doing here.

---

## How it works

OpenPigeon is a **Madrid extension**. Madrid is the extension interface used by
[OpenBubbles](https://openbubbles.app), and it is what OpenPigeon implements.

    ┌─────────────────┐   binds    ┌──────────────────────┐
    │  Your app       │ ─────────► │  OpenPigeon          │
    │  (extension     │            │  MadridExtension     │
    │   host)         │ ◄───────── │  Service             │
    └─────────────────┘  callbacks └──────────────────────┘

Your app is the **host**. It discovers installed extensions, binds to them,
renders the `RemoteViews` they return, and sends the messages they produce.
OpenPigeon is the **extension**. It supplies the game picker keyboard, runs the
games, and hands back message payloads.

Both apps stay separate and update independently.

## Requirements

Your app must implement the Madrid extension host side. The interface
definitions live in the `com.bluebubbles.messaging` package and are maintained
by the BlueBubbles project, not by OpenPigeon:

- `IMadridExtension`  the extension binder
- `IMessageViewHandle`  host handle for updating a sent message
- `IKeyboardHandle`  host handle for the keyboard surface
- `IViewUpdateCallback`  extension asks the host to re-render
- `ITaskCompleteCallback`  completion signal for async host work
- `MadridMessage`  the message payload object

See the [BlueBubbles project](https://github.com/BlueBubblesApp) for canonical
definitions and their licensing. Copies exist in this repository under
`app/src/main/aidl/com/bluebubbles/messaging/` for build purposes only.

Because this is BlueBubbles' interface rather than ours, a host that works with
OpenBubbles will generally work with OpenPigeon without OpenPigeon-specific
code.

## Detecting OpenPigeon

OpenPigeon's package name is `com.openbubbles.openpigeon`.

```kotlin
fun isOpenPigeonInstalled(context: Context): Boolean =
    try {
        context.packageManager.getPackageInfo("com.openbubbles.openpigeon", 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }
```

On Android 11 (API 30) and above, add a `<queries>` entry to your manifest or
the lookup fails even when OpenPigeon is installed:

```xml
<queries>
    <package android:name="com.openbubbles.openpigeon" />
</queries>
```

If OpenPigeon is not installed, send the user to the Play Store rather than
failing silently:

    https://play.google.com/store/apps/details?id=com.openbubbles.openpigeon

## Binding

Bind to:

    com.openbubbles.openpigeon.MadridExtensionService

`onBind` returns a singleton `MadridExtension` implementing `IMadridExtension`.
The instance is created on first bind and cleared in `onDestroy`, so it does not
survive process death. Do not cache the binder across reconnects. Rebind and
call `keyboardOpened` again after the extension process is killed.

### Callbacks the host invokes

| Method | When                                                                      |
|---|---------------------------------------------------------------------------|
| `keyboardOpened(callback, handle, userCount)` | User opens the extension drawer. Returns the game-picker `RemoteViews`.   |
| `keyboardClosed()` | Drawer dismissed.                                                         |
| `getLiveView(callback, message, handle, userCount)` | Host needs to render an OpenPigeon message bubble. Returns `RemoteViews`. |
| `didTapTemplate(message, handle, userCount)` | User taps a game bubble. OpenPigeon launches the game activity.           |
| `messageUpdated(message)` | An existing message changed - new turn received.                          |

`userCount` is the number of participants in the conversation. OpenPigeon uses
it to hide games that require more players than are present.

### Sessions

`MadridMessage.session` identifies a game thread. OpenPigeon keys its internal
`GameSession` map on it, and reuses the session when the same value arrives
again. Your host must **preserve `session` unchanged** across the whole life of
a game. If it regenerates, OpenPigeon treats each turn as a new game and state
is lost.

The host supplies a fresh `IMessageViewHandle` on each call; OpenPigeon swaps it
into the existing session automatically.

### Locking

OpenPigeon calls `handle.lock()` while a game is in progress and `handle.unlock()`
when it finishes. Your host should use this to prevent the user editing or
sending over a message that is mid-update.

## Message payloads

OpenPigeon produces a `MadridMessage` with these fields set:

| Field | Contents |
|---|---|
| `messageGuid` | Fresh random UUID per message |
| `session` | Game thread identifier  preserve verbatim (see above) |
| `url` | `data:` payload, described below |
| `ldText` | Human-readable game name, e.g. `Word Hunt` |
| `caption` | Status line, e.g. `Your Move.` |
| `subcaption` | Optional secondary line |
| `imageBase64` | JPEG preview, base64 `NO_WRAP`, quality 55. Null on continuation turns where the host already has a preview. |
| `isLive` | Always `true` |

### The `url` field

The payload is a URL-encoded query string, obfuscated, wrapped in a second query
string, and prefixed with `data:`:

    data:?ver=52&data=<obfuscated>

To read it, replace the `data:` scheme with `data://` so it parses as a URI,
take the `data` parameter, de-obfuscate it, then parse the result as another
query string:

```kotlin
val uri = message.url.replace("data:", "data://").toUri()
val inner = deobfuscate(uri.getQueryParameter("data")!!)
val fields = "data://$inner".toUri()   // now read query parameters
```

`ver=52` is the outer format version. It has not changed.

### Inner fields

| Key | Meaning |
|---|---|
| `game` | Game identifier, e.g. `wordhunt`, `pool`, `crazy8` |
| `game_name` | Display name |
| `sender` | UUID of whoever sent this turn |
| `player1`, `player2` | Participant UUIDs. A device whose UUID matches neither is spectating. |
| `avatar2` | Sender's encoded avatar |
| `winner` | `<uuid>\|<flag>`  see below. Absent while the game is in progress. |
| `caption`, `subcaption` | Display strings |
| `version`, `tver`, `num`, `build`, `ios` | Format and compatibility markers |
| `id` | Random 12-byte base64 identifier |
| *(game-specific)* | Each game adds its own state keys |

Player identity is a UUID generated on first use and stored in the
`openpigeon` shared preferences under `sender_uuid`. It is per-install, not tied
to any account, and never leaves the device except inside these payloads.

### The `winner` field

Format `<uuid>|<flag>`:

- `flag == "0"` - draw
- `flag == "-1"` - the named UUID **lost**; the other player won
- otherwise - the named UUID won

The inversion exists because some games determine the result on the losing
player's device.

### What the host must preserve

Your host stores and re-sends these messages. Treat `url` and `session` as
**opaque and immutable**. Do not re-encode, normalize, trim, or URL-decode the
`url` field. The obfuscation is position-sensitive and any alteration corrupts
the game state irrecoverably.

## Obfuscation, not encryption

The `data` parameter is passed through `Cryption`, which is a **deterministic
character permutation**, not encryption:

- The permutation is generated by a `drand48`-style PRNG seeded with
  `payloadLength * 0xef`
- There is no key, no secret, and no per-message variation
- Two payloads of the same length use the same permutation

It exists to match GamePigeon's wire format, so that OpenPigeon on Android and
GamePigeon on iOS can exchange messages. **It provides no confidentiality.**
Anyone with the payload can recover the plaintext.

For a host application this means:

- You do not need keys, and there is nothing to configure
- Treat the payload as opaque, but do not treat it as secure
- Do not put anything sensitive in game state
- If your transport is encrypted, that is what protects the payload and not this

## Behavior when OpenPigeon is absent

A received OpenPigeon message with no OpenPigeon installed should degrade
gracefully. We suggest a placeholder showing the game name with a prompt to
install, rather than an error or an empty bubble. `ldText` is suitable for the
label without needing to parse the payload.

## GamePigeon compatibility

OpenPigeon games interoperate with Apple's GamePigeon message format, which is
what allows play between OpenPigeon on Android and GamePigeon on iOS. Your host
does not need to do anything to enable this as it is handled inside OpenPigeon,
and is the reason the payload format above is shaped the way it is.

## Support

Questions about integrating: **support@openbubbles.app**, or ask on Discord.

Questions about the Madrid interface itself are better directed to the
BlueBubbles project, since the interface is theirs.