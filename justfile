set windows-shell := ["cmd.exe", "/c"]

# Default recipe
default:
    @just --list

# Run the whole continuous integration pipeline
ci:
    zig build ci --summary all

# Compile every artifact without running it
check:
    zig build check --summary all

# Compile every artifact for Linux from any host
check-linux:
    zig build check -Dtarget=x86_64-linux-gnu --summary all

# Compile every artifact for Windows from any host
check-windows:
    zig build check -Dtarget=x86_64-windows-gnu --summary all

# Build the application and install artifacts
build:
    zig build

# Build and run the application
run:
    zig build run

# Run every test suite
test:
    zig build test:unit test:mock --summary all

# Run the colocated unit tests and the tidy law, optionally filtered: just unit tidy
unit filter="":
    zig build test:unit --summary all -- {{filter}}

# Run the end to end tests against the mock backends, optionally filtered
mock filter="":
    zig build test:mock --summary all -- {{filter}}

# Run the tidy check on its own
tidy:
    zig build test:unit -- tidy

# Check that every source file is formatted
fmt:
    zig build test:fmt

# Format every source file in place
format:
    zig fmt build.zig src

# systemd owns the timeout from outside the launching process tree, so the
# instance is SIGKILLed on schedule even if the shell that started it dies or
# the process wedges while blocking input. Killing the process closes the
# evdev grabs and destroys the uinput devices, which restores the physical
# keyboard and mouse. Use this for any test where a broken unlock path could
# leave the peripherals locked.
#
# Run a build with a hard kill deadline enforced by systemd, for testing on Linux
[unix]
run-timed seconds="30": build
    systemd-run --user --collect --property=RuntimeMaxSec={{seconds}} --property=TimeoutStopSec=2 {{justfile_directory()}}/zig-out/bin/locker

# The committed .rgba files are raw 32x32 8 bit per channel RGBA taken from the
# 32 bit 32x32 frame of each .ico, which is index 12 in the icon directory. The
# 8 bit frames carry a 1 bit AND mask in place of an alpha channel, so taking
# one of those aliases every edge and flattens the artwork to its palette. The
# frame is already 32x32, so it is copied out without a resize. src/icon.zig
# moves the alpha channel to the front at comptime, because that is the ARGB
# order umbra ships to both backends.
#
# Regenerate the tray pixmaps from the icon sources
[unix]
icons:
    convert 'asset/lock.ico[12]' -depth 8 rgba:asset/lock.rgba
    convert 'asset/unlock.ico[12]' -depth 8 rgba:asset/unlock.rgba

# Build with release safety checks
release:
    zig build -Doptimize=ReleaseSafe

# Build the smallest release binary
release-small:
    zig build -Doptimize=ReleaseSmall

# Clean build artifacts
[unix]
clean:
    rm -rf zig-out .zig-cache

# Clean build artifacts
[windows]
clean:
    if exist zig-out rmdir /s /q zig-out
    if exist .zig-cache rmdir /s /q .zig-cache
