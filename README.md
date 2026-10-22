# tk46v6b-devenv

Local build environment for the [tk46v6b](https://github.com/tadakado/tk46v6b)
ZMK keyboard firmware (macOS + colima/Docker + the ZMK devcontainer).

This repo holds the glue and pins the exact commit of everything else as
git submodules:

| Path | Source |
| --- | --- |
| `zmk/` | upstream [zmkfirmware/zmk](https://github.com/zmkfirmware/zmk) (shallow) |
| `zmk-config/` | [tadakado/tk46v6b](https://github.com/tadakado/tk46v6b) |
| `zmk-modules/*` | [zmk-ir](https://github.com/tadakado/zmk-ir), [zmk-rgb-indicator](https://github.com/tadakado/zmk-rgb-indicator), [zmk-ble-debug](https://github.com/tadakado/zmk-ble-debug), [zmk-bootloader-1200](https://github.com/tadakado/zmk-bootloader-1200), [zmk-ble-mouse-host](https://github.com/tadakado/zmk-ble-mouse-host) |

## Setup (fresh machine)

Requires `git`, `docker`, `colima`, and the `devcontainer` CLI. Clone **under
your home directory**: colima only shares `~` with the Docker VM, so a clone in
e.g. `/tmp` fails with "bind source path does not exist".

```sh
git clone --recurse-submodules https://github.com/tadakado/tk46v6b-devenv.git
cd tk46v6b-devenv
./0_setup.sh            # colima + bind volumes for zmk-config / zmk-modules
./1_start.sh            # start the devcontainer (first run: west init + update)
make build
```

Container image: `docker.io/zmkfirmware/zmk-dev-arm:4.1-branch`
(from `zmk/.devcontainer`).

## Day to day

| Command | What it does |
| --- | --- |
| `./1_start.sh` / `./2_stop.sh` | start / stop the container and colima |
| `make check_env` | verify the container is bound to this checkout (runs before every build) |
| `make build` | build left + right (also `left`, `right`, `devkit`, `settings_reset`) |
| `make flash_left` etc. | copy the UF2 to the bootloader drive (one board at a time), e.g. `./flash.sh && make flash_left` |
| `./flash.sh` | enter the UF2 bootloader via a 1200-baud touch, then wait for the drive to mount (`FLASH_WAIT`, default 20 s) |
| `./console.sh` | ZMK log console with auto-reconnect |
| `./backup_firmware.sh` | snapshot built UF2s with the git revision they came from |
| `./9_clean_volumes.sh` | remove the container and volumes (sources stay on disk) |

## Local-only files

`local/zmk-config/` holds `Makefile` and `*.zmk.yml`. `zmk-config/.gitignore`
excludes them (the cloud build does not use them), so the root `Makefile`
forwards every target to `local/zmk-config/Makefile`, run from `zmk-config/`.
Run `make ...` from the repo root and edit the real files in `local/zmk-config/`.

## Local Zephyr patches

`patches/zephyr/*.patch` are applied to the Zephyr tree inside the container
(the `zmk-zephyr` docker volume, fetched by `west update`, not part of this
repo). `make` refuses to build unless they are all applied.

```sh
./zephyr_patch.sh status          # applied / not-applied / CONFLICT per patch
./zephyr_patch.sh apply           # then rebuild: make -B left (Zephyr is not a make dependency)
./zephyr_patch.sh revert
```

- `0001-llcp-reset-incompat-after-rejected-peripheral-cpr`: fixes ~2.5 s
  host-link drops with HCI reason 0x24 (seen with macOS) when LE Ping is on.
  The firmware keeps LE Ping at its default (on) and relies on this patch.
- The patches survive container restarts / `0_setup.sh` / `9_clean_volumes.sh`,
  but not `docker volume rm zmk-zephyr`; a `west update` that changes the Zephyr
  revision may undo them -- `check_env` will tell.
- GitHub Actions builds of tk46v6b use **unpatched** Zephyr.

## Updating pinned versions

Each submodule is pinned to a commit. After pulling/committing inside one:

```sh
git -C zmk fetch && git -C zmk checkout <rev>     # or: cd zmk-modules/zmk-ir && git pull
git add zmk                                        # record the new pin
git commit -m "Bump zmk"
```
**Push the submodule's own repo first**, otherwise a fresh clone cannot fetch
the pinned commit. After bumping `zmk`, re-run `west update` in the container.

## Troubleshooting

- `make` stops with "Container zmk-dev is bound to another folder": the
  container's `/workspaces/zmk` mount or the `zmk-config` / `zmk-modules`
  volumes belong to a different checkout (whichever last ran `0_setup.sh` /
  `1_start.sh`). Re-bind to this one: `./0_setup.sh && ./1_start.sh`.
  `0_setup.sh` removes `zmk-dev` first, because `docker volume rm` fails while
  a container still holds the volumes and the old binding would silently stay.

- `./1_start.sh` fails with a `zmk-dev` name conflict: `docker rm -f zmk-dev`, re-run.
- "not a valid zephyr module": the bind volumes are stale. Remove every
  container that uses them (`docker rm -f $(docker ps -aq --filter volume=zmk-modules)`),
  then re-run `./0_setup.sh`.
- `bind source path does not exist`: the clone is outside `~` (see Setup).
