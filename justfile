set shell := ["sh", "-c"]
set windows-shell := ["powershell.exe", "-c"]

bin := home_directory() / ".local/bin"
data := env("XDG_DATA_HOME", home_directory() / ".local/share")
release := justfile_directory() / "zig-out/release"
units := env("XDG_CONFIG_HOME", home_directory() / ".config") / "systemd/user"

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

[doc('Regenerate the tray pixmaps and the desktop entry image from the icons')]
icons:
    magick 'assets/lock.ico[12]' -depth 8 rgba:assets/lock.rgba
    magick 'assets/unlock.ico[12]' -depth 8 rgba:assets/unlock.rgba
    magick 'assets/unlock.ico[8]' -strip assets/unlock.png

[doc('Build a release, install it, its user service, and its desktop entry, and restart the service on the new build')]
[linux]
install:
    zig build --release=safe --prefix '{{ release }}'
    install -D -m 755 '{{ release }}/bin/locker' '{{ bin }}/locker.new'
    mv -f '{{ bin }}/locker.new' '{{ bin }}/locker'
    install -D -m 644 contrib/locker.service '{{ units }}/locker.service'
    install -D -m 644 contrib/locker.desktop '{{ data }}/applications/locker.desktop'
    install -D -m 644 assets/unlock.png '{{ data }}/icons/hicolor/256x256/apps/locker.png'
    touch '{{ data }}/icons/hicolor'
    systemctl --user daemon-reload
    systemctl --user enable locker.service
    systemctl --user restart locker.service
    sleep 2
    systemctl --user is-active locker.service

[doc('Lint build.zig and every source file with tigerstyle-lsp')]
lint:
    tigerstyle-lsp check build.zig src --format concise

[default]
[doc('List every recipe')]
list:
    @just --list

[doc('Build and run the application')]
run:
    zig build run

[doc('Run the application under a systemd kill deadline: just run-timed [seconds]')]
[linux]
run-timed seconds="30":
    zig build
    systemd-run --user --collect --property=RuntimeMaxSec={{ seconds }} --property=TimeoutStopSec=2 {{ justfile_directory() }}/zig-out/bin/locker

[doc('Run every test suite and the format check')]
test:
    zig build test

[doc('Run the end to end tests against the fake backends: just test-fake [filter]')]
test-fake filter="":
    zig build test:fake {{ if filter == "" { "" } else { "-Dtest-filter=" + filter } }}

[doc('Run the unit tests and the tidy check: just test-unit [filter]')]
test-unit filter="":
    zig build test:unit {{ if filter == "" { "" } else { "-Dtest-filter=" + filter } }}
