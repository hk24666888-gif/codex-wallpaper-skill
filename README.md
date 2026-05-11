# Codex Wallpaper Skill

This repository contains a Codex skill for safely changing or restoring the Windows desktop sidebar wallpaper for Yukino or official Codex.

Install with Codex skill installer:

```powershell
python install-skill-from-github.py --repo hk24666888-gif/codex-wallpaper-skill --path skills/app-wallpaper
```

Or ask Codex to install:

```text
Install https://github.com/hk24666888-gif/codex-wallpaper-skill/tree/main/skills/app-wallpaper
```

The skill includes a PowerShell script that creates backups before patching `app.asar`, supports restore, and can target either `yukino` or `codex`.
