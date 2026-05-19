# OpenPigeon for OpenBubbles

OpenPigeon is a GamePigeon-compatible game pack for OpenBubbles on Android. OpenBubbles is used to access iMessage.

[![Play Store](https://openbubbles.app/google_play_badge.png)](https://play.google.com/store/apps/details?id=com.openbubbles.openpigeon)

OpenPigeon is fully open-source, and we're actively looking for game developers to contribute their favorite games.

## Supported Games
- 8 Ball (All Modes)
- 20 Questions
- Anagrams
- Archery
- Basketball (All Modes)
- Checkers (All Modes)
- Chess
- Crazy 8
- Cup Pong (All Modes)
- Darts (All Modes)
- Dots & Boxes
- Filler
- Four in a Row
- Gomoku
- Mancala
- Paintball
- Reversi
- Sea Battle (All Sizes)
- Tanks
- Wordbites
- Word Hunt (All Modes)

## Contributing
1. Git clone with Submodules. 
1. Open in Android Studio. 
1. Create an empty file named `config.properties` in the root folder.
1. Open `app/src/main/assets` in the Godot editor
1. Run in Android Studio and install to your device.
1. Rename your .exe of godot to `godot.exe` and edit the local.properties file under Gradle Scripts to include `godot.path={Path to godot.exe} (i.e godot.path=C\:\\Users\\franks\\programfiles\\godot.exe)` Ensure that double back slashes are used. 
1. Restart Android Studio
1. Enable developer mode in OpenBubbles -> Developer Tools.
1. Add the service name: `com.openbubbles.openpigeon.MadridExtensionService`

Contact us on Discord if you're interested in contributing and are looking for guidance.
