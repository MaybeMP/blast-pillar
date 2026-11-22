# Getting Blast Pillar onto your iPhone (free)

GitHub builds the iPhone app for you on a free Mac, then Sideloadly puts it on your phone
using your normal Apple ID. No paid developer account needed.

## One-time setup

### 1. Put the project on GitHub (GitHub Desktop, no typing commands)
1. Make a free account at https://github.com
2. Install GitHub Desktop from https://desktop.github.com and sign in.
3. File > Add local repository > choose `C:\dev\Godot\ios\blast-pillar`.
   It will say it's not a repository yet - click **create a repository**, keep the name, click Create.
4. Click **Publish repository**.
   - Untick "Keep this code private" if you don't mind it being public: public projects get
     unlimited free builds. Private ones share a small monthly allowance of free Mac minutes
     (enough for roughly 15-20 builds a month).
5. Publishing starts the first build automatically.

### 2. Get the app file
1. On your repository's GitHub page, open the **Actions** tab.
2. Click the newest **Build iPhone app** run and wait for the green tick (about 10-15 minutes the
   first time, faster after that).
3. Scroll down to **Artifacts** and download **BlastPillar-iPhone**. Unzip it to get `BlastPillar.ipa`.

### 3. Install Sideloadly and Apple's helpers on your PC
1. Install iTunes **from Apple's website, not the Microsoft Store**: https://www.apple.com/itunes/download/win64
2. Install iCloud for Windows (Sideloadly's site links the right version).
3. Install Sideloadly: https://sideloadly.io
4. Restart the PC.

### 4. Install on the iPhone
1. Plug the iPhone into the PC, unlock it, and tap **Trust** if it asks.
2. Open Sideloadly. Drag `BlastPillar.ipa` onto it, type your Apple ID email, click **Start**,
   and sign in when asked.
3. On the iPhone: Settings > General > VPN & Device Management > tap your Apple ID > **Trust**.
4. Settings > Privacy & Security > **Developer Mode** > On (the phone restarts; confirm after).
5. Open Blast Pillar from the home screen.

## Every time after that
- New version: commit and **Push origin** in GitHub Desktop, wait for the build, download the
  new `.ipa`, and install it with Sideloadly again (your save stays on the phone).
- Free Apple IDs only sign apps for **7 days**. When the app stops opening, just install the
  same `.ipa` again with Sideloadly.
- A free Apple ID can have up to 3 sideloaded apps at once.

## Notes
- The build uses Godot 4.7.2 (set in `.github/workflows/ios.yml`). If you update Godot on your PC,
  change `GODOT_VERSION` there to match.
- `export_presets.cfg` holds the iPhone export settings (portrait, iPhone only,
  app id com.miles.blastpillar). The App Store team ID in it is a placeholder - it isn't needed
  because Sideloadly signs the app.
