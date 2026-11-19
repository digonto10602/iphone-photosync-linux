# iPhone → Linux PC with PhotoSync

Back up iPhone videos and photos to a Linux PC over Wi-Fi with the
[PhotoSync](https://www.photosync-app.com/) app, and watch the transfer live from the
[Omarchy](https://omarchy.org/) top bar.

PhotoSync's desktop companion app exists only for Windows and macOS, so on Linux the phone
sends to a server on the PC instead. This kit provides that server, keeps the uploads sorted,
and shows the progress.

## What's in it

| Part | File | What it does |
|---|---|---|
| WebDAV server | `systemd/iphone-webdav.service` | Serves `~/iphone_backup` on port 8080 using [rclone](https://rclone.org/) and a password login. Measured at about 74 MB/s average from an iPhone over Wi-Fi, compared with 7–9 MB/s for SFTP. |
| Sorter | `bin/iphone-backup-sorter`, `systemd/iphone-backup-sorter.service` | Moves photos into `images/` and videos into `videos/`, keeping the date sub-folder each file arrived in. Live Photo clips stay next to their still. Byte-identical duplicates are removed and other name clashes get `_1`, `_2`, … |
| Progress feed / terminal view | `bin/iphone-transfers` | Live terminal view (`iphone-transfers`), a JSON feed (`--json`) for the bar widget, and `--set-total N` to set how many files the phone is sending. |
| Bar widget | `omarchy-plugin/iphone-transfers/` | Phone icon with a progress ring on the Omarchy bar. Click it for a see-through, theme-coloured panel showing the progress ring, speed graph, files done out of the total, time left and each arriving file. |
| Auto pop-up | `bin/iphone-transfers-autoopen`, `systemd/iphone-transfers-autoopen.service` | Opens the bar panel when a new WebDAV transfer starts. |
| Launcher entry | `applications/iphone-transfers.desktop` | "iPhone Transfers" in the app launcher; opens the terminal view. |

### How progress is known
The PC is never told the final size of an upload. iPhone `.MOV`/`.MP4` files begin with a
header that states the size of the video data (the `mdat` box), so the final size is read from
it. The small index at the end of the file (about 0.03%) isn't counted until it arrives. For
photos only the bytes received are shown. The overall time left is
`(bytes still missing in files in flight + files not started × average size so far) ÷ speed over the last 20 s`.

## Install

```bash
git clone https://github.com/digonto10602/iphone-photosync-linux
cd iphone-photosync-linux
./install.sh
```

Then follow the steps it prints: install rclone, open port 8080 to your home network, enable
the bar widget, and configure PhotoSync.

### PhotoSync settings (WebDAV)
- **Server:** the PC's local IP. **Port:** 8080. **SSL:** off.
- **Login / password:** from `~/.config/iphone-webdav/env`.
- **Directory:** `/videos`. The server's top folder is already `~/iphone_backup`, so don't type the full Linux path.
- **Create Sub-Directories:** Recording Date (Year + Month), which gives folders like `videos/2026/11/`.
- **Video format:** Original.
- Send with **All** or **Selected**. **New** skips files PhotoSync thinks it already sent.

## Requirements
- Linux with systemd user services, Python 3, `inotify-tools`, `psmisc` (`fuser`), `ffmpeg` (`ffprobe`), `jq`.
- `rclone` for the WebDAV server.
- Omarchy (Hyprland + Quickshell) for the bar widget and auto pop-up. Everything else works without it.

## Security notes
- WebDAV here is plain HTTP. Keep it on a trusted home network and allow port 8080 only from your LAN subnet in the firewall.
- The password lives in `~/.config/iphone-webdav/env` (mode 600) and is **not** part of this repository.
- SFTP (port 22, encrypted) keeps working as a slower alternative.

## Uninstall
```bash
systemctl --user disable --now iphone-webdav iphone-backup-sorter iphone-transfers-autoopen
omarchy plugin disable digimonk.iphone-transfers
rm ~/.local/bin/iphone-{backup-sorter,transfers,transfers-autoopen} \
   ~/.config/systemd/user/iphone-{webdav,backup-sorter,transfers-autoopen}.service \
   ~/.local/share/applications/iphone-transfers.desktop
rm -r ~/.config/omarchy/plugins/iphone-transfers
```
