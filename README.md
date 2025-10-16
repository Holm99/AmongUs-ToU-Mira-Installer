# Among Us — ToU-Mira Installer (Steam-only)

Install, update, repair, or restore **Among Us** with the **Town of Us Mira** mod, plus optional **BetterCrewLink** — all from a simple menu.

---

## 🚀 One-liner (quick start)

**Open Windows PowerShell** and run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass; irm https://raw.githubusercontent.com/Holm99/AmongUs-ToU-Mira-Installer/main/au-mod-installer.ps1 | iex
```

Prefer `iwr`? Use:

```powershell
iwr -useb https://raw.githubusercontent.com/Holm99/AmongUs-ToU-Mira-Installer/main/au-mod-installer.ps1 | iex
```

You can also press Win+R and run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr -useb https://raw.githubusercontent.com/Holm99/AmongUs-ToU-Mira-Installer/main/au-mod-installer.ps1 | iex"
```

## 🤔 How do I open PowerShell?

1. **Close** Among Us and Steam.
2. Press **Start** and type **PowerShell**.
3. Click **Windows PowerShell** (blue icon).
   - If you later see “access denied” errors, **right-click → Run as administrator** and try again.
4. **Copy** the one-liner above, **paste** into PowerShell, and press **Enter**.


## ✅ Requirements

- **Windows 10/11**
- **PowerShell 5.1** (built-in)
- **Steam copy of Among Us** installed  
  (You can manually browse to the folder if auto-detect misses it.)
- Internet access to GitHub
- A few GB free disk space for the backup

---

## 🧭 What you’ll see

An interactive menu with live status (installed versions and available updates):

- **1) Install Among Us – ToU-Mira**  
  Guides you to **Verify Integrity** in Steam (manual step), creates a full **backup** (`Among Us - Bck`), applies the latest **TOU-Mira**, and offers to **install BetterCrewLink**.

- **2) Update**  
  Smart update that checks both **TOU-Mira** and **BetterCrewLink**:
  - If only one needs an update, it updates that automatically.
  - If both have updates, you’ll get an **Update Menu** (All / Mod only / BCL only).
  - Mod updates restore vanilla first, then re-apply the latest TOU-Mira.

- **3) Restore Vanilla**  
  Deletes the current `Among Us` folder, renames your backup back to `Among Us`, removes backup metadata, and (optionally) **uninstalls BetterCrewLink**.

- **4) Install BetterCrewLink**  
  Detects existing installs, offers **reinstall** (with proper silent uninstall), fetches the **latest** release dynamically, and launches its installer.

- **5) Repair**  
  Tools to fix things quickly:
  - **Repair All** (restore vanilla + reapply latest mod, then fix BCL)
  - **Repair Mod (TOU-Mira)**
  - **Repair BetterCrewLink**

After each action, the script cleans up its working folder:
`%USERPROFILE%\Downloads\AmongUsModInstaller`

---

## 📝 Logging & where things go

- **Log file:** `%USERPROFILE%\Downloads\au-installer-latest.log`  
  Includes an environment snapshot and detailed steps (downloads, robocopy logs, etc.).
- **Backup folder:** `Among Us - Bck` (sibling to your `Among Us` folder)  
  Contains a small `.au_backup_meta.json` so the script can verify integrity.
- **Working folder (auto-cleaned):** `%USERPROFILE%\Downloads\AmongUsModInstaller`

---

## 🔐 What the script does (and doesn’t)

- Finds your Steam library locations and the **Among Us** folder.
- Creates a full backup (`Among Us - Bck`) before applying mods.
- Pulls **latest** releases directly from GitHub.
- Cleans up its own working folder in **Downloads** after each run.
- **Does not** touch other games or your Steam installation.

> If files are locked, make sure **Among Us and Steam are closed**. Also **close any File Explorer windows** that are open inside the `Among Us` folder (Explorer can keep files in use, especially with **Preview**/**Details** pane enabled). Then try again.

---

## 🛠 Troubleshooting

- **“Running scripts is disabled” / execution policy errors**  
  The one-liner uses a **process-scoped bypass** and should work. If you still see errors, start PowerShell **as Administrator**.

- **“Could not locate Among Us”**  
  Choose the folder manually when prompted. It must contain `Among Us.exe`.

- **“Folder in use” / “Access is denied” / file locked**  
  File Explorer can hold locks on files if you’re viewing the game folder.
  1) **Close** all File Explorer windows opened to the `Among Us` folder (or any of its subfolders).  
  2) If needed, switch Explorer to a neutral location like **This PC** or **Desktop**.  
  3) Turn off the **Preview pane** (**Alt+P**) and **Details pane** (**Alt+Shift+P**).  
  4) Wait a few seconds and rerun the script.  
  5) Still locked? Press **Ctrl+Shift+Esc** → find **Windows Explorer** → **Restart**. As a last resort, **reboot**.

- **Permission denied / file in use from other apps**  
  Close overlays and tools that may touch the folder (Discord/Steam overlays, backup/sync tools, antivirus scans), then retry.

---

## 📦 Upstream projects

- Town of Us Mira: <https://github.com/AU-Avengers/TOU-Mira>  
- BetterCrewLink: <https://github.com/OhMyGuus/BetterCrewLink>

---

## 🧾 License & contributions

- **License:** MIT — see [`LICENSE`](./LICENSE) for the full text.  
- **Copyright:** © 2025 **Holm99**.  
- **Contributions:** Issues and PRs are welcome! By submitting a contribution, you agree to license your work under the MIT License.  
- **Note:** This installer references third-party projects (TOU-Mira, BetterCrewLink) which are distributed under their own licenses. Please review their respective LICENSE files.
- This project is community-maintained and not affiliated with Innersloth, AU-Avengers, or BetterCrewLink.

---

## 🔎 Read before you run (optional)

Want to inspect the script first? Open it in your browser:  
<https://raw.githubusercontent.com/Holm99/AmongUs-ToU-Mira-Installer/main/au-mod-installer.ps1>






