# psu_control

[![CI](https://github.com/joern-h/psu_control/actions/workflows/ci.yml/badge.svg)](https://github.com/joern-h/psu_control/actions/workflows/ci.yml)

Control suite for the **Owon SPE6103** bench power supply (60 V / 10 A), written
in Dart and Flutter. The repository is a Dart workspace with three components and
one shared library:

| Package | Kind | Purpose |
|---|---|---|
| `packages/psu_service` | Dart daemon | **Only process that touches the serial port.** Polls measurements, keeps a sample history and serves clients over WebSocket. |
| `packages/psu_cli` | Dart CLI (`psu`) | Status, setpoints, output on/off, power cycle, live watch, raw SCPI. |
| `apps/psu_ui` | Flutter desktop app | Live readout, setpoint entry, output switch, editable presets, voltage and current charts. |
| `packages/psu_protocol` | Dart library | Message types and the `PsuClient` used by CLI and UI. |

```
            ┌──────────┐    WebSocket (JSON)    ┌─────────────┐   /dev/ttyPowerSupply   ┌──────────┐
  psu_ui ───┤          ├───────────────────────▶│             │──── SCPI 115200 8N1 ────▶│ SPE6103  │
  psu  ─────┤ clients  │                        │ psu_service │                          │          │
            └──────────┘◀───── events ──────────│             │◀─────────────────────────│          │
                                                └─────────────┘                          └──────────┘
```

## Requirements

* Flutter SDK (Dart ≥ 3.13), Linux desktop toolchain for the UI
  (`clang`, `cmake`, `ninja`, `pkg-config`, `libgtk-3-dev`).
* The PSU reachable as `/dev/ttyPowerSupply` (udev rule, see
  `deploy/99-owon-psu.rules.example`) and read/write permission for your user.
* `stty` (coreutils). The service configures the port with it and then uses
  plain file I/O, so there is no native serial library to build.

## Quick start

```bash
dart pub get                                         # resolves the whole workspace

# 1. service (keeps running, Ctrl-C to stop)
dart run packages/psu_service/bin/psu_service.dart -v

# 2. CLI
dart run packages/psu_cli/bin/psu_cli.dart status
dart run packages/psu_cli/bin/psu_cli.dart set --voltage 5 --current 0.5
dart run packages/psu_cli/bin/psu_cli.dart on
dart run packages/psu_cli/bin/psu_cli.dart watch           # live line, Ctrl-C to stop
dart run packages/psu_cli/bin/psu_cli.dart watch --csv -s 10 > log.csv
dart run packages/psu_cli/bin/psu_cli.dart cycle           # off, 3 s pause, on (only while output is on)
dart run packages/psu_cli/bin/psu_cli.dart cycle 5 10      # sleep 10 s, off, 5 s pause, on
dart run packages/psu_cli/bin/psu_cli.dart off
dart run packages/psu_cli/bin/psu_cli.dart scpi 'MEAS:ALL?'

# 3. UI
cd apps/psu_ui && flutter run -d linux
```

## Installing

```bash
deploy/install.sh              # compiles everything into ~/.local (bin/ + share/)
deploy/install.sh --systemd    # additionally installs and enables the user unit
deploy/install.sh --no-ui      # service + CLI only (no Flutter build)
PREFIX=/opt/psu deploy/install.sh
deploy/uninstall.sh
```

This puts `psu_service`, `psu` and `psu_ui` into `$PREFIX/bin` (make sure
`~/.local/bin` is in your `PATH`), the Flutter bundle into
`$PREFIX/share/psu_control/ui/`, the app icon into the hicolor icon theme and
a desktop entry "PSU Control" into the application menu. The icon source is
`apps/psu_ui/linux/icon/psu-control.svg`; the PNG sizes next to it are
rendered with `rsvg-convert` and checked in. The window sets its own icon from
`<bundle>/data/psu-control.png`, and `StartupWMClass` matches the GTK
application id so taskbars group the window with the launcher.

### Service lifecycle

CLI and UI start the service themselves when it is not reachable, so after
installing you can simply run `psu status` or open the UI. The launcher tries,
in order: `systemctl --user start psu_service` (if the unit is installed),
`$PSU_SERVICE_BIN`, `psu_service` next to the running binary,
`~/.local/bin/psu_service`, `psu_service` on `PATH`, and finally `dart run` on
the service package when running from a source checkout.

A service started this way is detached from the terminal and logs to
`~/.local/state/psu_control/service.log`. Manage it with:

```bash
psu service status
psu service start
psu service stop        # graceful shutdown via the protocol
psu service restart
psu --no-autostart status   # fail instead of starting the service
```

## UI presets

The presets card below the setpoints applies a stored voltage (and optionally a
current limit) with one click. Presets can be added, edited, deleted and
reordered by dragging; they are stored in `~/.config/psu_control/presets.json`
and seeded with 5 / 9 / 12 / 24 / 48 V on first start.

Note: release builds must be made with `--no-tree-shake-icons` (the install
script does this); otherwise Flutter's icon tree-shaker drops glyphs used in
the presets card.

## Service options

```
psu_service [options]
-d, --device    Serial device node (default /dev/ttyPowerSupply)
-b, --bind      Listen address (default 127.0.0.1)
-p, --port      Listen port (default 8765)
    --poll-ms   Measurement interval in ms (default 200)
    --history   Seconds of samples kept for new clients (default 3600)
    --log-file  Append log output to a file instead of stderr
-v, --verbose   Log client connections
```

The service reconnects automatically when the device disappears and tolerates
single missed replies. Setpoints changed on the front panel are picked up every
two seconds.

## Wire protocol

JSON text frames over WebSocket (`ws://127.0.0.1:8765`).

Request → response:

```json
{"id": 1, "type": "setVoltage", "value": 12.0}
{"id": 1, "ok": true, "result": { ...PsuState... }}
{"id": 2, "ok": false, "error": "voltage must be between 0 and 60.0 V"}
```

Request types: `getState`, `getHistory` (`seconds` optional), `setVoltage`
(`value`), `setCurrent` (`value`), `setOutput` (`on`), `scpi` (`command`),
`shutdown`.

Events pushed to every client:

```json
{"event": "sample", "data": {"t": 1793807283010, "v": 12.001, "i": 0.254}}
{"event": "state",  "data": { ...PsuState... }}
```

`PsuState` fields: `connected`, `identity`, `setVoltage`, `setCurrent`,
`outputOn`, `ovpLimit`, `ocpLimit`, `lastSample`, `error`.

## SCPI commands used (verified on SPE6103, firmware V5.5.0)

Serial: 115200 baud, 8N1, no flow control. Commands end with `\n`, replies with
`\r\n`. Set commands do not reply.

| Command | Reply |
|---|---|
| `*IDN?` | `OWON,SPE6103,<serial>,FV:V5.5.0` |
| `VOLT?` / `VOLT 12.000` | `12.000` |
| `CURR?` / `CURR 2.000` | `2.000` |
| `OUTP?` / `OUTP ON` / `OUTP OFF` | `ON` / `OFF` |
| `MEAS:VOLT?` `MEAS:CURR?` `MEAS:POW?` | `0.000` |
| `MEAS:ALL?` | `<volts>,<amps>` |
| `VOLT:LIM?` / `CURR:LIM?` | OVP / OCP threshold |

`SYST:STAT?` and `*OPC?` return garbage on this firmware and are not used.

## Contributing

Bug reports and pull requests are welcome. Before opening a PR run
`dart format .`, `dart analyze` and make sure `deploy/install.sh` still
builds; CI runs the same checks. Changes to the SCPI layer should state on
which model and firmware they were verified.

## Disclaimer

This is an independent hobby project and is not affiliated with or endorsed
by OWON. It switches a real power supply on and off; use it at your own risk
and double-check setpoints and limits before enabling the output.

## License

[MIT](LICENSE)
