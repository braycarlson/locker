set shell := ["sh", "-c"]
set windows-shell := ["powershell.exe", "-c"]

[doc('Compile every artifact without running it')]
check:
    zig build check

[doc('Compile every artifact for Linux from any host')]
check-linux:
    zig build check -Dtarget=x86_64-linux-gnu

[doc('Compile every artifact for Windows from any host')]
check-windows:
    zig build check -Dtarget=x86_64-windows-gnu

[doc('Run the continuous integration pipeline')]
ci:
    zig build ci
    zig build test:unit -Doptimize=safe

[doc('Format build.zig and every source file')]
fmt:
    zig fmt build.zig src

[doc('Regenerate the tray pixmaps from the icons')]
[unix]
icons:
    convert 'assets/lock.ico[12]' -depth 8 rgba:assets/lock.rgba
    convert 'assets/unlock.ico[12]' -depth 8 rgba:assets/unlock.rgba

[default]
[doc('List every recipe')]
list:
    @just --list

[doc('Run the end to end tests against the mock backend: just mock [filter]')]
mock filter="":
    zig build test:mock {{ if filter == "" { "" } else { "-Dtest-filter=" + filter } }}

[doc('Build and run the application')]
run:
    zig build run

[doc('Run the application under a systemd kill deadline: just run-timed [seconds]')]
[unix]
run-timed seconds="30":
    zig build
    systemd-run --user --collect --property=RuntimeMaxSec={{ seconds }} --property=TimeoutStopSec=2 {{ justfile_directory() }}/zig-out/bin/locker

[doc('Run every test suite and the format check')]
test:
    zig build test

[doc('Run the unit tests and the tidy check: just unit [filter]')]
unit filter="":
    zig build test:unit {{ if filter == "" { "" } else { "-Dtest-filter=" + filter } }}
