# Autopilot Hash Upload

Register Windows laptops in Intune Autopilot directly from the OOBE screen — no manual CSV export/import through the Intune portal.

## What this does

Normally, registering a device in Windows Autopilot means:

1. Boot the laptop → export the hardware hash to a CSV
2. Go to the Intune portal → import the CSV
3. Wait for sync

This project skips steps 1–3. Run a single command at OOBE, sign in with your own admin account, and the device is registered and assigned in one go.

## Prerequisites

- An account with Intune permissions to register Autopilot devices (`DeviceManagementServiceConfig.ReadWrite.All` or equivalent role)
- Internet access on the machine (needed for Autopilot anyway)
- Windows 10/11

No app registration, client ID, or secret is required — this uses interactive sign-in, so nothing sensitive is stored in the script.

## Usage

At the Windows OOBE screen (language/keyboard selection):

1. Press `Shift + F10` to open a command prompt
2. Run:

   ```
   cd C:\Temp
   curl -o run.bat https://raw.githubusercontent.com/shubhuzone/autopilot-hash-upload/refs/heads/main/run-cloud.bat
   run.bat
   ```

3. Enter a Group Tag when prompted (or leave blank)
4. Sign in with your admin account when the login window appears
5. Wait for "Upload completed successfully" — the device will restart automatically and re-check in at OOBE to pick up its Autopilot profile

## Files

| File | Purpose |
|---|---|
| `run-cloud.bat` | Entry point — downloads the PowerShell script and runs it |
| `Upload-AutopilotHash-Interactive.ps1` | Collects the hardware hash and uploads it to Intune via `Get-WindowsAutopilotInfo` |

## Logs

If something goes wrong, check `C:\ProgramData\AutopilotUpload\upload.log` on the machine you ran it on.

## Status

This is in active testing. It's been verified end-to-end (sign-in → hash collection → Intune upload → auto-restart) on a test machine. Feedback and issues welcome.

## License

MIT — see [LICENSE](LICENSE).
