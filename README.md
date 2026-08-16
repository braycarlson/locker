<p align="center">
    <picture>
        <source media="(prefers-color-scheme: dark)" srcset="assets/locker-wordmark-on-dark.svg">
        <source media="(prefers-color-scheme: light)" srcset="assets/locker-wordmark-on-light.svg">
        <img alt="locker" src="assets/locker-wordmark-on-light.svg" width="320">
    </picture>
</p>

&nbsp;

<p align="center">
    A tray application that locks your keyboard and mouse on Windows and Linux.
</p>

<p align="center">
    <a href="https://github.com/braycarlson/locker/actions/workflows/ci.yml"><img alt="ci" src="https://img.shields.io/github/actions/workflow/status/braycarlson/locker/ci.yml?branch=main&amp;style=flat-square&amp;label=ci"></a>
    <a href="https://ziglang.org"><img alt="zig" src="https://img.shields.io/badge/zig-0.16.0-orange.svg?style=flat-square"></a>
    <a href="LICENSE"><img alt="license" src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square"></a>
</p>

## Overview

locker locks the keyboard and the mouse. The default is `ctrl+alt+l` to lock and the typed
word `UNLOCK` to release it. A lock swallows input at the hook rather than grabbing a
device, so the keyboard and mouse stay attached and the unlock path keeps working.

## Features

- **Separate locks**: The keyboard and the mouse lock on their own, from the tray menu or
  the configuration.
- **Unlock by word**: The release is a typed sequence, so a stray keypress cannot end the
  lock by accident. A key combination works too.
- **Remaps and disables**: A rule sends one combination to another, and a disabled entry
  drops it, up to 64 of each.
- **Live configuration**: The file is watched, so an edit takes effect without a restart.
- **Rehooking**: A timer reinstalls the hook every ten minutes, since Windows drops a hook
  that takes too long.

## Install

Each tagged release carries a Linux and a Windows build.

The build from source looks for [nimble](https://github.com/braycarlson/nimble) and
[wisp](https://github.com/braycarlson/wisp) in the same parent directory, since
`build.zig.zon` points at them by relative path. It fetches
[arc](https://github.com/braycarlson/arc) by URL.

```
git clone https://github.com/braycarlson/nimble
git clone https://github.com/braycarlson/wisp
git clone https://github.com/braycarlson/locker
cd locker
zig build -Doptimize=ReleaseSafe
```

The binary lands in `zig-out/bin`. locker requires Zig 0.16.0.

## Usage

The application lives in the tray. The menu toggles the lock as a whole, toggles the
keyboard and the mouse on their own, opens the configuration file, and exits.

| Action | Default |
|---|---|
| Lock | The `ctrl+alt+l` combination. |
| Unlock | The typed sequence `UNLOCK`. |
| Locked on lock | The keyboard, with the mouse left alone. |
| Notification | The tray balloon, shown on each change. |

Linux needs the `nimbled` daemon from [nimble](https://github.com/braycarlson/nimble),
which its `contrib/systemd` installer sets up along with the `uinput` permission.

## Configuration

The file is `config.zon` under the platform's configuration directory. The defaults are
written there on first run. A key is a single character or a name such as `f1`,
`capslock`, or `escape`, and a modifier is `ctrl`, `alt`, `shift`, or `win`.

```zig
.{
    .is_keyboard_locked = true,
    .is_mouse_locked = false,
    .show_notification = true,
    .lock = .{ .key = "l", .modifiers = .{ "ctrl", "alt" } },
    .unlock = .{ .sequence = "UNLOCK" },
    .disabled = .{
        .{ .key = "f1" },
    },
    .remap = .{
        .{ .from = .{ .key = "capslock" }, .to = .{ .key = "escape" } },
    },
}
```

A shortcut takes either a `key` with optional `modifiers` or a `sequence`, so the unlock
can be a chord instead of a word. The log sits beside the configuration and rotates at
five megabytes.

## Development

The recipes below wrap `zig build`, and a bare `just` lists them all. The tidy law is a
test rather than a separate linter, so the mechanical rules run with everything else.

| Command | What it runs |
|---|---|
| `just ci` | The formatting check, compilation, and the test suites. |
| `just test` | The unit tests and the mock suite. |
| `just tidy` | The tidy law on its own. |
| `just run` | The application from source. |
| `just run-timed [seconds]` | The application under a systemd scope that kills it, for a Linux session. |
| `just check-windows` | The compile of every artifact for Windows from any host. |

## Licence

MIT. See [LICENSE](LICENSE).
