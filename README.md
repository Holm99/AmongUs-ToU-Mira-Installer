# Among Us — ToU Mira Installer (Steam only)

Install, update, or restore **Among Us** with the **Town of Us Mira** mod, plus optional **BetterCrewLink** — all from a simple menu.

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

---

## 🤔 How do I open PowerShell?

1. **Close** Among Us and Steam.
2. Press **Start** and type **PowerShell**.
3. Click **Windows PowerShell** (blue icon).
   - If you later see “access denied” errors, **right-click → Run as administrator** and try again.
4. **Copy** the one-liner above, **paste** into PowerShell, and press **Enter**.

You can also press **Win+R**, paste the line below, and press **Enter**:

```
powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr -useb https://raw.githubusercontent.com/Holm99/AmongUs-ToU-Mira-Installer/main/au-mod-installer.ps1 | iex"
```

---

## 🧭 What you’ll see

An interactive menu:

- **1) Install Among Us – ToU Mira**  
  Guides you to **Verify Integrity** in Steam (manual step), makes a **backup** (`Among Us - Bck`), applies the latest **ToU Mira**, and offers to **install BetterCrewLink** at the end.

- **2) Update**  
  Restores **vanilla**, you run Steam **Verify**, then it **re-installs the latest ToU Mira**.

- **3) Restore Vanilla**  
  Deletes modded `Among Us`, renames your backup back to `Among Us`, removes backup metadata, and asks if you want to **uninstall BetterCrewLink**.

- **4) Install BetterCrewLink**  
  Detects existing installs, offers **reinstall** (with proper silent uninstall), fetches the **latest** BetterCrewLink release dynamically, and runs its installer.

After each action, the script cleans up its working folder:
`%USERPROFILE%\Downloads\AmongUsModInstaller`

---

## ✅ Requirements

- **Windows 10/11**
- **PowerShell 5.1** (built-in on Windows 10/11)
- **Steam copy of Among Us** installed  
  (You can manually point to the folder if auto-detect misses it.)
- Internet access to GitHub
- A few GB free disk space for backup

---

## 🔐 What the script does (and doesn’t)

- Finds your Steam library locations and the **Among Us** folder.
- Creates a full backup (`Among Us - Bck`) before applying mods.
- Pulls **latest** releases directly from GitHub.
- Cleans up its own working folder in **Downloads** after each run.
- **Does not** touch other games or your Steam installation.

> If files are locked, make sure **Among Us and Steam are closed**.

---

## 🛠 Troubleshooting

- **“Running scripts is disabled” / execution policy errors**  
  The one-liner uses a **process-scoped bypass** and should work. If you still see errors, start PowerShell **as Administrator**.

- **“Could not locate Among Us”**  
  Choose the folder manually when prompted. It must contain `Among Us.exe`.

- **Permission denied / file in use**  
  Close Among Us, Steam, and overlays (e.g., Discord), then retry.

---

## 📦 Upstream projects

- Town of Us Mira: <https://github.com/AU-Avengers/TOU-Mira>  
- BetterCrewLink: <https://github.com/OhMyGuus/BetterCrewLink>

---

## 🧾 License & contributions

Feel free to open issues and PRs. Consider MIT for the script (add a `LICENSE` file if you like).

---

## 🔎 Read before you run (optional)

Want to inspect the script first? Open it in your browser:  
<https://raw.githubusercontent.com/Holm99/AmongUs-ToU-Mira-Installer/main/au-mod-installer.ps1>
