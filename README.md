# Among Us — TOU-Mira Installer

Install, update, uninstall, or repair the **Town of Us Mira** mod for **Among Us** (Steam), plus optional **BetterCrewLink** proximity voice chat — all from one simple menu. No manual file copying required.

**What is TOU-Mira?** It's a community-made modification (mod) for Among Us that adds new roles, game modes, and features on top of the base game.

**What is BetterCrewLink?** A separate, optional tool that adds proximity voice chat to Among Us — you can hear nearby players through their microphone. You do **not** need it to use TOU-Mira.

---

## How to use (step by step)

### Step 1: Close everything

**Close Among Us** if it's running. **Close Steam** too — this prevents "file in use" errors.

### Step 2: Open PowerShell

1. Press the **Start** button (bottom-left of your screen) or the **Windows key** on your keyboard.
2. Type **PowerShell**.
3. Click **Windows PowerShell** (the blue icon).

> **Tip:** If you get "access denied" errors later, close this window, go back to the Start menu, **right-click** Windows PowerShell, then click **Run as administrator**.

### Step 3: Paste this command and press Enter

Copy this entire line, paste it into the blue PowerShell window, then press **Enter**:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass; irm https://raw.githubusercontent.com/Holm99/AmongUs-ToU-Mira-Installer/main/au-mod-installer.ps1 | iex
```

> **How to paste in PowerShell:** Right-click anywhere inside the window, or press **Ctrl+V**.

### Step 4: Follow the on-screen menu

The installer will find your Among Us folder automatically and show you a menu. Type a number (or letter) and press **Enter** to pick an option. That's it!

### After installation

Once the installer is done, just **launch Among Us through Steam** like you normally would. The mod loads automatically — no extra setup needed.

---

## What each menu option does

### 1) Install TOU-Mira

Downloads and installs the latest TOU-Mira mod into your Among Us folder. Your original (vanilla) game files are never changed — the mod only adds new files alongside them.

After installing, the script checks if you have BetterCrewLink:
- **Not installed?** Asks if you'd like to install it.
- **Already installed but outdated?** Offers to update it.
- **Already up-to-date?** Skips automatically.

### 2) Update

Checks if newer versions of TOU-Mira or BetterCrewLink are available.
- If **one** has an update, it updates automatically.
- If **both** have updates, you'll get a submenu to choose: Update All, Update TOU-Mira only, or Update BetterCrewLink only.
- Mod updates cleanly remove old mod files first, then apply the new version. Your vanilla game files are never touched.

### 3) Uninstall TOU-Mira

Removes **only** the mod files and returns your game to the original, unmodified ("vanilla") Among Us. Your save data and vanilla game files are completely safe. Also offers to uninstall BetterCrewLink if detected.

### 4) Install BetterCrewLink

Installs the BetterCrewLink proximity voice chat tool. If it's already installed, offers to reinstall it. For **updates**, use option 2 (Update) instead.

### 5) Repair

Fixes a broken or corrupted mod install. You'll get a submenu:
- **Repair All** — fixes both TOU-Mira and BetterCrewLink
- **Repair Mod (TOU-Mira)** — removes the current mod files and downloads a fresh copy
- **Repair BetterCrewLink** — reinstalls BetterCrewLink

> **Update vs. Repair:** Use **Update** (option 2) when a new version is available and you want to upgrade. Use **Repair** (option 5) when your current install is broken or not working, and you want to reinstall the same (or latest) version from scratch.

### F) Toggle fast mode

Turns off the typewriter text animation so menus appear instantly. Press F again to turn it back on. Your preference is saved for next time.

### Q) Quit

Exits the installer and cleans up temporary files.

---

## Requirements

- **Windows 10 or 11**
- **Among Us** installed through **Steam**
- Internet connection (the installer downloads from GitHub)

That's it. PowerShell 5.1 is already included with Windows 10 and 11 — you don't need to install anything extra.

---

## Frequently asked questions

### "It says running scripts is disabled"

The command above includes a bypass for this. If you still see the error, close PowerShell and reopen it **as Administrator** (right-click, Run as administrator), then try again.

### "It can't find my Among Us folder"

The installer searches your Steam library automatically. If it can't find it, it will ask you to pick the folder manually. Navigate to your Among Us folder — it's the one that contains `Among Us.exe`.

**Common location:** `C:\Program Files (x86)\Steam\steamapps\common\Among Us`

If you installed Steam to a different drive or folder, look for a `steamapps\common` folder inside wherever Steam is installed.

### "Access denied" or "file in use" errors

Something is locking your game files. Try these steps in order:

1. **Close Among Us and Steam** completely (check the system tray near the clock — Steam sometimes hides there).
2. **Close File Explorer** if you have the Among Us folder open — Explorer can lock files even when you're just browsing.
3. Turn off the **Preview pane** in File Explorer if it's on (**Alt+P** to toggle it).
4. Close any overlays or tools that might touch the folder (Discord overlay, antivirus, backup/sync tools).
5. Wait a few seconds, then try again.
6. **Still stuck?** Restart your computer and run the installer before opening anything else.

### "What if a Steam update comes out?"

Just update through Steam like normal. The mod only adds extra files — it never changes vanilla Among Us files. After a Steam update you may need to update the mod too (use option 2 in the menu).

### "How do I go back to vanilla Among Us?"

Use **option 3 (Uninstall TOU-Mira)** in the menu. It removes only the mod files and leaves your vanilla game untouched.

### "Can I inspect the script before running it?"

Yes! Open this link in your browser to read the full source code:
<https://raw.githubusercontent.com/Holm99/AmongUs-ToU-Mira-Installer/main/au-mod-installer.ps1>

---

## How it works (technical details)

The installer is a single PowerShell script. Here's what it does behind the scenes:

- **Finds your game** by reading Steam's registry keys and library config files.
- **Downloads mod files** directly from the official [TOU-Mira GitHub releases](https://github.com/AU-Avengers/TOU-Mira/releases).
- **Adds mod files** into your game folder alongside existing files (never modifies or replaces vanilla game files).
- **Tracks what it installed** using a small file (`.au_installer_manifest.json`) inside your game folder — a record of every mod file added, so it can cleanly remove them later during uninstall or update.
- **Saves your preferences** (game folder location, fast mode) in a config file (`.au_installer_config.json`) so you don't have to re-enter them next time.
- **Cleans up** its temporary download folder (`%USERPROFILE%\Downloads\AmongUsModInstaller`) after each action.
- **Logs everything** to `%USERPROFILE%\Downloads\au-installer-latest.log` for troubleshooting.

The script **does not** modify vanilla game files, touch other games, or change your Steam installation.

---

## Alternative ways to run

If the main command doesn't work for you, try one of these instead:

**Using `iwr`:**
```powershell
iwr -useb https://raw.githubusercontent.com/Holm99/AmongUs-ToU-Mira-Installer/main/au-mod-installer.ps1 | iex
```

**Using Win+R (Run dialog):**
```
powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr -useb https://raw.githubusercontent.com/Holm99/AmongUs-ToU-Mira-Installer/main/au-mod-installer.ps1 | iex"
```

---

## Upstream projects

- Town of Us Mira: <https://github.com/AU-Avengers/TOU-Mira>
- BetterCrewLink: <https://github.com/OhMyGuus/BetterCrewLink>

---

## License & contributions

- **License:** MIT — see [`LICENSE`](./LICENSE) for the full text.
- **Copyright:** © 2025 **Holm99**.
- **Contributions:** Issues and PRs are welcome! By submitting a contribution, you agree to license your work under the MIT License.
- **Note:** This installer references third-party projects (TOU-Mira, BetterCrewLink) which are distributed under their own licenses. Please review their respective LICENSE files.
- This project is community-maintained and not affiliated with Innersloth, AU-Avengers, or BetterCrewLink.
