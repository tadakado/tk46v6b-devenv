# tk46v6b-devenv

Local build environment for the [tk46v6b](https://github.com/tadakado/tk46v6b)
ZMK keyboard firmware (macOS + colima/Docker + the ZMK devcontainer).

This repo holds only the glue. The code itself lives in:

| Path | Source |
| --- | --- |
| `zmk/` | upstream [zmkfirmware/zmk](https://github.com/zmkfirmware/zmk), pinned in `bootstrap.sh` |
| `zmk-config/` | [tadakado/tk46v6b](https://github.com/tadakado/tk46v6b) |
| `zmk-modules/*` | [zmk-ir](https://github.com/tadakado/zmk-ir), [zmk-rgb-indicator](https://github.com/tadakado/zmk-rgb-indicator), [zmk-ble-debug](https://github.com/tadakado/zmk-ble-debug), [zmk-bootloader-1200](https://github.com/tadakado/zmk-bootloader-1200), [zmk-ble-mouse-host](https://github.com/tadakado/zmk-ble-mouse-host) |

## Setup (fresh machine)

Requires `git`, `docker`, `colima`, and the `devcontainer` CLI.

```sh
git clone https://github.com/tadakado/tk46v6b-devenv.git
cd tk46v6b-devenv
./bootstrap.sh          # clone zmk (pinned), zmk-config, modules
./0_setup.sh            # colima + bind volumes for zmk-config / zmk-modules
./1_start.sh            # start the devcontainer (first run: west init + update)
cd zmk-config && make build
```

Container image: `docker.io/zmkfirmware/zmk-dev-arm:4.1-branch`
(from `zmk/.devcontainer`).

## Day to day

| Command | What it does |
| --- | --- |
| `./1_start.sh` / `./2_stop.sh` | start / stop the container and colima |
| `make build` (in `zmk-config/`) | build left + right (also `left`, `right`, `devkit`, `settings_reset`) |
| `make flash_left` etc. | copy the UF2 to the bootloader drive (one board at a time) |
| `./flash.sh` | enter the UF2 bootloader via a 1200-baud touch |
| `./console.sh` | ZMK log console with auto-reconnect |
| `./backup_firmware.sh` | snapshot built UF2s with the git revision they came from |
| `./9_clean_volumes.sh` | remove the container and volumes (sources stay on disk) |

## Local-only files

`local/zmk-config/` holds `Makefile` and `*.zmk.yml`. `zmk-config/.gitignore`
excludes them (the cloud build does not use them), so `bootstrap.sh` symlinks
them into `zmk-config/`. Edit them in `local/zmk-config/`.

## Updating the pinned ZMK

```sh
git -C zmk fetch && git -C zmk checkout <rev>
```
Then update `ZMK_REV` in `bootstrap.sh` and re-run `west update` in the container.

## Troubleshooting

- `./1_start.sh` fails with a `zmk-dev` name conflict: `docker rm -f zmk-dev`, re-run.
- "not a valid zephyr module": the bind volumes are stale. Remove every
  container that uses them (`docker rm -f $(docker ps -aq --filter volume=zmk-modules)`),
  then re-run `./0_setup.sh`.
