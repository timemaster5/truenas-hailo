# truenas-hailo

Keeps the Hailo-8 PCIe driver (`hailo_pci.ko` plus firmware) working on TrueNAS SCALE across
OS upgrades and reboots, so apps that use `/dev/hailo0` (Frigate, for example) keep working.

TrueNAS ships no Hailo driver and the module only loads into the exact kernel it was built for.
After an upgrade the old module is rejected and `/dev/hailo0` is gone. This project rebuilds the
module for the running kernel and loads it, without writing to the root filesystem.

## How it works

- The build runs in a Docker container (Debian bookworm). Kernel headers, `/lib/modules` and
  `/boot` are mounted read-only; the only writable paths are the project directory's `out/`
  and `cache/`. Nothing is installed on the TrueNAS root filesystem.
- The driver source is fetched from `hailo-ai/hailort-drivers` by tag and verified against a
  pinned sha256.
- Modules are kept per kernel (`out/<kernel>/hailo_pci.ko`), so booting an older boot
  environment finds its module again without a rebuild.
- Two init tasks, registered through TrueNAS Init/Shutdown Scripts:
  - PREINIT `hailo-preinit.sh`: sets the firmware path and loads the module for the running
    kernel if one has been built already. No Docker needed, so apps start with the device present.
  - POSTINIT `hailo-ensure.sh --detach`: if `/dev/hailo0` is missing, waits for Docker (bounded),
    builds for the running kernel, loads it, and stops/starts the apps listed in `APPS`.
    It runs in the background and is locked against concurrent runs.

After an upgrade the first boot therefore has no device until the build finishes (a few
minutes); the POSTINIT run then restarts the configured apps. Later boots on the same kernel
use the PREINIT fast path only.

## Install

Run on the TrueNAS host. Without `--apply` it only prints what it would do.

    git clone <this repo> && cd truenas-hailo
    ./install.sh --dest /mnt/tank/hailo        # dry run, prints commands
    ./install.sh --dest /mnt/tank/hailo --apply

Pick a path on a pool dataset (or leave the default `/root/truenas-hailo`). Then edit
`<dest>/hailo.conf` (driver version, checksums, `APPS="ix-frigate"` style app names as shown by
`midclt call app.query | jq -r '.[].name'`) and run once by hand:

    <dest>/hailo-ensure.sh

Remove the init tasks with `./install.sh --uninstall --apply` (files are left in place).
Delete any older hand-made Hailo init tasks yourself; they would load a stale module.

## Frigate

Pass the device through in the app's configuration (`/dev/hailo0`) and set the detector to
`hailo8l` / `hailo8` as in the Frigate docs. Add the app name to `APPS` so it is restarted when
the driver had to be loaded after the app started. TrueNAS 25.10 has no `app.restart`, so the
script uses `app.stop` then `app.start`.

## Tested

| TrueNAS SCALE | kernel | Hailo-8 driver |
|---|---|---|
| 25.10.6 | 6.12.99 | 4.21.0 |
| 25.10.8 | 6.12.113 | 4.21.0 |

Hailo-8 only (hailort-drivers 4.x). Hailo-8L uses the same driver but is untested here.

## Troubleshooting

- Log: `<dest>/hailo.log`, also `journalctl -t truenas-hailo`.
- `disagrees about version of symbol module_layout`: the module was built for another kernel.
  Remove nothing; run `hailo-ensure.sh` and it builds the right one into `out/<kernel>/`.
- `kernelrelease != running kernel`: the headers under `/usr/src` do not match the booted kernel
  (for example a pending update). Reboot into the installed version and retry.
- Build fails at once: Docker not running (Apps pool not set) or no network for the source download.
- `/dev/hailo0` missing though the module is loaded: firmware not found. Check
  `<dest>/out/firmware/hailo/hailo8_fw.bin` exists; the firmware path is set via
  `/sys/module/firmware_class/parameters/path`.
- Apps do not see the device after a late load: list them in `APPS`, or `app.stop` / `app.start` by hand.

## License

MIT. The Hailo driver is GPL-2.0 and is downloaded at build time, not distributed here.
