# Ant Simulator 2026 — Build Notes

Prototype built 2026-10-14. Debug APK: `build/ant-simulator-2026-debug.apk`
(package `com.antsim2026.prototype`, signed with `~/.android/debug.keystore`).

## Toolchain (all local, reusable)
- Godot 4.7.2 headless: `~/tools/godot/Godot_v4.7.2-stable_linux.x86_64`
- Export templates: `~/.local/share/godot/export_templates/4.7.2.stable/`
- JDK 17 (Temurin): `~/tools/jdk-17`
- Android SDK: `~/Android/Sdk` (cmdline-tools, platform-tools, build-tools 34.0.0, platforms/android-34)
- Env: `source ~/Android/env.sh` (sets JAVA_HOME, ANDROID_HOME/SDK_ROOT, GRADLE_USER_HOME, locale, tmpdir)

## Gotchas (do not re-learn the hard way)
1. `/tmp` is a 512MB tmpfs — never download large files there. Use `~/tmp` (and
   `_JAVA_OPTIONS=-Djava.io.tmpdir=$HOME/tmp`).
2. sdkmanager fails through the egress proxy (Java CONNECT tunneling bug).
   Workaround used: download `build-tools_r34-linux.zip` and the android-34
   platform zip with curl from dl.google.com and unzip manually into the SDK.
3. Gradle daemon cannot communicate in this sandbox (client connects, daemon
   never receives the build — root cause undiagnosed). Workaround used:
   **non-Gradle export** (`gradle_build/use_gradle_build=false` in
   export_presets.cfg). This uses the prebuilt android_debug.apk template —
   fine for a pure-GDScript game with no custom plugins. Remember to clear
   `gradle_build/min_sdk` and `gradle_build/target_sdk` overrides when Gradle
   is off, or the export preset fails validation.
4. Android build template must live at `res://android/build/` (NOT
   `res://android/`), with `res://android/.build_version` containing exactly
   `4.7.2.stable` and an empty `res://android/build/.gdignore`. Replicate the
   editor's "Install Android Build Template" manually if needed.
5. `JAVA_TOOL_OPTIONS=-Dfile.encoding=UTF-8` + `LANG=C.UTF-8` needed (Java 17
   defaults to US-ASCII here otherwise).
6. We run as root with HOME=/home/hatch — Java's user.home is /root, so always
   export GRADLE_USER_HOME explicitly.

## Game smoke test
Headless autotest exercises digging, foraging, spider spawn and combat.
The main scene is now the menu, so the game scene is passed explicitly:
`godot --headless --fixed-fps 60 --path . res://scenes/main.tscn --quit-after 3600 -- --autotest`
Look for `AUTOTEST:` lines and zero `SCRIPT ERROR`s.

## Rebuild
```
source ~/Android/env.sh
~/tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path ~/workspace/ant-simulator-2026 \
  --export-debug "Android" ~/workspace/ant-simulator-2026/build/ant-simulator-2026-debug.apk
```
