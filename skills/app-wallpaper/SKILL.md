---
name: app-wallpaper
description: Safely change, inspect, or restore the sidebar/background wallpaper inside the Windows Yukino or Codex desktop app. Use when the user asks to change Yukino wallpaper, Codex wallpaper, sidebar background, app background image, restore a broken wallpaper patch, or package a repeatable wallpaper-changing workflow for Yukino/Codex.
---

# App Wallpaper

Use this skill for Windows Yukino/Codex desktop wallpaper changes. It edits the desktop app package, so always prefer the bundled script over manual `app.asar` edits.

## Workflow

1. Ask for the target app if unclear: `yukino` or `codex`.
2. Ask for an image file if applying a wallpaper. Use an absolute local image path.
3. Run `scripts/app_wallpaper.ps1`:

```powershell
# Inspect current state
powershell -ExecutionPolicy Bypass -File scripts/app_wallpaper.ps1 -Mode status -Target yukino

# Apply a wallpaper
powershell -ExecutionPolicy Bypass -File scripts/app_wallpaper.ps1 -Mode apply -Target yukino -ImagePath "D:\Pictures\wallpaper.png"

# Restore latest backup
powershell -ExecutionPolicy Bypass -File scripts/app_wallpaper.ps1 -Mode restore -Target yukino
```

Use `-Target codex` for the official Codex desktop app.

## Safety Rules

- Always run `status` first.
- Always use `apply` through the script; do not hand-edit `app.asar`.
- The script creates timestamped backups before changing anything.
- If the app fails to open or the UI looks wrong, run `restore`.
- Do not delete backups until the user confirms the app has worked across a restart.

## Notes

- Requires Windows PowerShell, Node.js, and `npx`.
- The script uses `@electron/asar` through `npx` to patch the app bundle.
- The app may need to be restarted after applying or restoring.
