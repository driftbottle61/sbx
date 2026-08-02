# SBX

SBX is an interactive Sing-box manager for Debian and Ubuntu. It installs and
upgrades Sing-box, manages its configuration and systemd service, and provides
TUN/TProxy routing tools.

## Install

Run as `root`, or pipe the script to `sudo bash`:

```bash
curl -fsSL https://raw.githubusercontent.com/driftbottle61/sbx/main/install.sh | sudo bash
```

With `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/driftbottle61/sbx/main/install.sh | sudo bash
```

Then start the manager:

```bash
sudo sbx
```

The same install command upgrades SBX. Existing `/opt/sbx/data/sbx.conf` is
preserved during an upgrade.

## Install a release or fork

```bash
curl -fsSL https://raw.githubusercontent.com/driftbottle61/sbx/main/install.sh \
  | sudo bash -s -- --ref v1.2.0
```

```bash
curl -fsSL https://raw.githubusercontent.com/OWNER/REPO/main/install.sh \
  | sudo SBX_REPO=OWNER/REPO bash
```

Use `--skip-deps` if all required system packages are already installed.

## Uninstall

Remove SBX while leaving the Sing-box binary and `/etc/sing-box` in place:

```bash
sudo /opt/sbx/uninstall.sh
```

Add `--keep-data` to copy the SBX and Sing-box configuration into a timestamped
directory under `/var/lib` before removal.

## Files

- `/opt/sbx`: SBX application files
- `/usr/local/bin/sbx`: command entry point
- `/etc/sing-box/config.json`: Sing-box configuration
- `/etc/systemd/system/sing-box.service`: generated systemd service

## Supported systems

- Debian and Ubuntu
- `amd64`, `arm64`, and `armv7` for Sing-box downloads

## License

MIT
