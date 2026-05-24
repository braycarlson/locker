set shell := ["cmd", "/c"]

# Default recipe
default:
    @just --list

# Build the application (mode: debug, release-safe, release-fast, release-small)
build mode="debug":
    cls && just clean && zig build {{ if mode == "debug" { "" } else if mode == "release-safe" { "-Doptimize=ReleaseSafe" } else if mode == "release-fast" { "-Doptimize=ReleaseFast" } else if mode == "release-small" { "-Doptimize=ReleaseSmall" } else { "" } }} && zig-out\bin\locker.exe

# Clean build artifacts
clean:
    cls
    if exist zig-out rd /s /q zig-out
    if exist .zig-cache rd /s /q .zig-cache

# Build in release mode (ReleaseSafe)
release:
    cls && just clean && zig build -Doptimize=ReleaseSafe
