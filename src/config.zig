const std = @import("std");

const nimble = @import("nimble");
const toml = @import("toml");
const umbra = @import("umbra");

const assert = std.debug.assert;

const Key = nimble.Key;
const Keycode = nimble.Keycode;
const Modifier = nimble.Modifier;

const CapacityError = toml.CapacityError || error{
    ContentTooLong,
    DisablesExhausted,
    PathTooLong,
    RemapsExhausted,
    ScratchExhausted,
    SequenceTooLong,
};

const PlatformError = error{
    ReadFailed,
    WriteFailed,
};

const SettingsError = error{
    CharacterInvalid,
    ContentInvalid,
    KeyInvalid,
    KeyMissing,
    SequenceEmpty,
};

const LoadError = PathError || ReadError;
const ParseError = CapacityError || SettingsError;
const PathError = umbra.CapacityError || umbra.PlatformError;
const ReadError = error{FileMissing} || CapacityError || PlatformError || SettingsError;
const content_bytes_max: u32 = 64 * 1024;
pub const directory_name = "locker";
const disabled_count_max: u32 = 64;
const document_node_count_max: u32 = 2048;
const document_text_bytes_max: u32 = 4096;
const file_name = "config.toml";
const file_name_legacy = "config.zon";
const modifier_kind_count: u32 = @typeInfo(Modifier.Kind).@"enum".field_names.len;
const remap_count_max: u32 = 64;
const scratch_bytes_max: u32 = 128 * 1024;
const write_bytes_max: u32 = 4096;

const writer_options: toml.Writer.Options = .{
    .layout = .compact,
    .strings = .auto,
    .version = .v1_1,
};

const Document = toml.DocumentType(.{
    .line_count_max = null,
    .node_count_max = document_node_count_max,
    .text_bytes_max = document_text_bytes_max,
});

const TomlShortcut = struct {
    key: ?[]const u8 = null,
    modifiers: ?[]const []const u8 = null,
    sequence: ?[]const u8 = null,
};

const TomlCombination = struct {
    key: []const u8,
    modifiers: ?[]const []const u8 = null,
};

const TomlRemap = struct {
    from: TomlCombination,
    to: TomlCombination,
};

const TomlConfig = struct {
    disabled: ?[]const TomlCombination = null,
    is_keyboard_locked: bool = true,
    is_mouse_locked: bool = false,
    lock: ?TomlShortcut = null,
    remap: ?[]const TomlRemap = null,
    show_notification: bool = true,
    unlock: ?TomlShortcut = null,
};

const default_toml = TomlConfig{
    .lock = .{ .key = "L", .modifiers = &.{ "ctrl", "alt" } },
    .unlock = .{ .sequence = "UNLOCK" },
};

comptime {
    const combination_node_count_max = 3 + modifier_kind_count;
    const shortcut_node_count_max = 1 + combination_node_count_max;
    const remap_node_count_max = 1 + 2 * combination_node_count_max;

    assert(content_bytes_max < scratch_bytes_max);
    assert(content_bytes_max <= toml.limits.source_bytes_max);
    assert(directory_name.len > 0);
    assert(disabled_count_max > 0);
    assert(document_text_bytes_max <= content_bytes_max);
    assert(file_name.len > 0);
    assert(!std.mem.endsWith(u8, file_name, file_name_legacy));
    assert(modifier_kind_count > 0);
    assert(remap_count_max > 0);
    assert(write_bytes_max > 0);

    assert(document_node_count_max >= 6 + 2 * shortcut_node_count_max +
        disabled_count_max * combination_node_count_max +
        remap_count_max * remap_node_count_max);
}

pub const Config = struct {
    content: [content_bytes_max + 1]u8,
    diagnostic: ?Diagnostic,
    disabled: [disabled_count_max]Combination,
    disabled_count: u32,
    document: Document,
    io: std.Io,
    is_keyboard_locked: bool,
    is_mouse_locked: bool,
    lock_shortcut: Shortcut,
    path: [umbra.limits.path_bytes_max]u8,
    path_length: u32,
    remap: [remap_count_max]RemapRule,
    remap_count: u32,
    scratch: [scratch_bytes_max]u8,
    show_notification: bool,
    unlock_shortcut: Shortcut,

    pub const Combination = struct {
        modifier_set: Modifier = .{},
        value: Keycode = .silent,

        pub fn is_valid(combination: *const Combination) bool {
            return combination.value != .silent;
        }

        pub fn match(combination: *const Combination, key: *const Key) bool {
            assert(combination.is_valid());

            if (combination.value != key.value) {
                return false;
            }

            return combination.modifier_set.eql(&key.modifiers);
        }
    };

    pub const Diagnostic = struct {
        position: toml.Position,
        reason: []const u8,
    };

    const RemapRule = struct {
        from: Combination,
        to: Combination,

        pub fn is_valid(rule: *const RemapRule) bool {
            return rule.from.is_valid() and rule.to.is_valid();
        }
    };

    const Sequence = struct {
        bytes: [nimble.limits.remote_sequence_bytes_max]u8 = @splat(0),
        length: u32 = 0,

        pub fn init(source: []const u8) ParseError!Sequence {
            if (source.len == 0) {
                return error.SequenceEmpty;
            }

            if (source.len > nimble.limits.remote_sequence_bytes_max) {
                return error.SequenceTooLong;
            }

            var result = Sequence{};

            for (source, 0..) |character, index| {
                if (!std.ascii.isAlphabetic(character)) {
                    return error.CharacterInvalid;
                }

                result.bytes[index] = std.ascii.toUpper(character);
            }

            result.length = @intCast(source.len);

            assert(result.is_valid());

            return result;
        }

        pub fn is_valid(sequence: *const Sequence) bool {
            return sequence.length > 0 and sequence.length <= sequence.bytes.len;
        }

        pub fn to_slice(sequence: *const Sequence) []const u8 {
            assert(sequence.is_valid());

            return sequence.bytes[0..sequence.length];
        }
    };

    const Shortcut = union(enum) {
        combination: Combination,
        sequence: Sequence,
    };

    pub fn init(config: *Config, io: std.Io) void {
        config.* = .{
            .content = undefined,
            .diagnostic = null,
            .disabled = @splat(.{}),
            .disabled_count = 0,
            .document = undefined,
            .io = io,
            .is_keyboard_locked = true,
            .is_mouse_locked = false,
            .lock_shortcut = default_lock_shortcut(),
            .path = @splat(0),
            .path_length = 0,
            .remap = @splat(.{ .from = .{}, .to = .{} }),
            .remap_count = 0,
            .scratch = undefined,
            .show_notification = true,
            .unlock_shortcut = default_unlock_shortcut(),
        };

        assert(config.get_path() == null);
        assert(config.diagnostic == null);
    }

    pub fn get_path(config: *const Config) ?[]const u8 {
        assert(config.path_length <= umbra.limits.path_bytes_max);

        if (config.path_length == 0) {
            return null;
        }

        return config.path[0..config.path_length];
    }

    pub fn is_disabled(config: *const Config, key: *const Key) bool {
        assert(config.disabled_count <= disabled_count_max);

        for (config.disabled[0..config.disabled_count]) |*entry| {
            if (entry.match(key)) {
                return true;
            }
        }

        return false;
    }

    pub fn load(config: *Config) LoadError!void {
        var buffer: [umbra.limits.path_bytes_max]u8 = undefined;

        const directory = try umbra.paths.config_dir(&buffer, directory_name);

        assert(directory.len > 0);

        try config.load_from(directory);
    }

    pub fn parse(config: *Config, content: []const u8) ParseError!void {
        assert(content.len > 0);
        assert(content.len <= content_bytes_max);

        config.diagnostic = null;

        const settings = try config.parse_toml(content);

        try config.apply(&settings);

        assert(config.diagnostic == null);
    }

    pub fn reload(config: *Config) (ReadError || ParseError)!void {
        config.diagnostic = null;

        const settings = try config.read_settings();

        try config.apply(&settings);

        assert(config.diagnostic == null);
        assert(config.get_path() != null);
    }

    pub fn remap_for(config: *const Config, key: *const Key) ?RemapRule {
        assert(config.remap_count <= remap_count_max);

        for (config.remap[0..config.remap_count]) |*rule| {
            if (rule.from.match(key)) {
                return rule.*;
            }
        }

        return null;
    }

    fn apply(config: *Config, settings: *const TomlConfig) ParseError!void {
        var lock_shortcut = default_lock_shortcut();
        var unlock_shortcut = default_unlock_shortcut();

        if (settings.lock) |lock| {
            lock_shortcut = try parse_shortcut(&lock);
        }

        if (settings.unlock) |unlock| {
            unlock_shortcut = try parse_shortcut(&unlock);
        }

        var staged_remap: [remap_count_max]RemapRule = undefined;
        var staged_remap_count: u32 = 0;

        if (settings.remap) |array| {
            staged_remap_count = try parse_remap_array(array, &staged_remap);
        }

        var staged_disabled: [disabled_count_max]Combination = undefined;
        var staged_disabled_count: u32 = 0;

        if (settings.disabled) |array| {
            staged_disabled_count = try parse_disabled_array(array, &staged_disabled);
        }

        config.is_keyboard_locked = settings.is_keyboard_locked;
        config.is_mouse_locked = settings.is_mouse_locked;
        config.show_notification = settings.show_notification;
        config.lock_shortcut = lock_shortcut;
        config.unlock_shortcut = unlock_shortcut;
        config.remap = staged_remap;
        config.remap_count = staged_remap_count;
        config.disabled = staged_disabled;
        config.disabled_count = staged_disabled_count;

        assert(config.remap_count <= remap_count_max);
        assert(config.disabled_count <= disabled_count_max);
    }

    fn load_from(config: *Config, directory: []const u8) LoadError!void {
        assert(directory.len > 0);

        try config.resolve_path(directory, file_name);

        config.reload() catch |err| switch (err) {
            error.FileMissing => try config.migrate(directory),
            else => |other| return other,
        };

        assert(config.get_path() != null);
        assert(config.diagnostic == null);
    }

    fn migrate(config: *Config, directory: []const u8) LoadError!void {
        assert(directory.len > 0);

        var buffer: [umbra.limits.path_bytes_max]u8 = undefined;

        const path = try join(&buffer, directory, file_name);

        try config.resolve_path(directory, file_name_legacy);

        const settings = config.read_settings() catch |err| switch (err) {
            error.FileMissing => default_toml,
            else => |other| return other,
        };

        try config.apply(&settings);
        try config.save(path, &settings);
        try config.resolve_path(directory, file_name);
        try config.reload();

        assert(config.path_length == path.len);
    }

    fn parse_legacy(config: *Config, content: [:0]const u8) ParseError!TomlConfig {
        assert(content.len > 0);
        assert(content.len <= content_bytes_max);

        var arena = std.heap.FixedBufferAllocator.init(&config.scratch);
        var diagnostics: std.zon.parse.Diagnostics = undefined;

        return std.zon.parse.fromSlice(TomlConfig, .{
            .gpa = arena.allocator(),
            .arena = arena.allocator(),
            .source = content,
            .diagnostics = &diagnostics,
        }) catch |err| switch (err) {
            error.OutOfMemory => return error.ScratchExhausted,
            error.ParseZon => return error.ContentInvalid,
        };
    }

    fn parse_toml(config: *Config, content: []const u8) ParseError!TomlConfig {
        assert(content.len > 0);
        assert(content.len <= content_bytes_max);

        config.document.parse(content, .{ .version = .v1_1 }) catch |err| {
            config.diagnostic = .{
                .position = config.document.diagnostic(),
                .reason = toml.message(err),
            };

            return switch (err) {
                error.DepthExceeded,
                error.NodesExhausted,
                error.TextExhausted,
                => |capacity| capacity,
                else => error.ContentInvalid,
            };
        };

        var position: toml.Position = undefined;
        var region: toml.Region = .init(&config.scratch);
        var result: TomlConfig = undefined;

        const document = &config.document.document;

        toml.decode(TomlConfig, &region, document, document.root(), &result, .{
            .diagnostic = &position,
            .unknown_members = .refused,
        }) catch |err| {
            config.diagnostic = .{ .position = position, .reason = toml.message(err) };

            return switch (err) {
                error.MemberMissing, error.MemberUnknown, error.Mismatch => error.ContentInvalid,
                error.RegionFull => error.ScratchExhausted,
            };
        };

        return result;
    }

    fn read(config: *Config, path: []const u8) ReadError![:0]const u8 {
        assert(path.len > 0);
        assert(path.len <= umbra.limits.path_bytes_max);

        const file = std.Io.Dir.openFileAbsolute(config.io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => return error.FileMissing,
            else => return error.ReadFailed,
        };

        defer file.close(config.io);

        const count = file.readPositionalAll(config.io, &config.content, 0) catch {
            return error.ReadFailed;
        };

        if (count == 0) {
            return error.ContentInvalid;
        }

        if (count > content_bytes_max) {
            return error.ContentTooLong;
        }

        config.content[count] = 0;

        return config.content[0..count :0];
    }

    fn read_settings(config: *Config) (ReadError || ParseError)!TomlConfig {
        const path = config.get_path() orelse return error.FileMissing;
        const content = try config.read(path);

        assert(content.len > 0);
        assert(content.len <= content_bytes_max);

        if (std.mem.endsWith(u8, path, file_name_legacy)) {
            return config.parse_legacy(content);
        }

        return config.parse_toml(content);
    }

    fn resolve_path(config: *Config, directory: []const u8, name: []const u8) CapacityError!void {
        config.path_length = 0;

        const full = try join(&config.path, directory, name);

        config.path_length = @intCast(full.len);

        assert(config.path_length > directory.len);
        assert(config.path_length <= umbra.limits.path_bytes_max);
    }

    fn save(
        config: *const Config,
        path: []const u8,
        settings: *const TomlConfig,
    ) (PlatformError || SettingsError)!void {
        assert(path.len > 0);
        assert(std.Io.Dir.path.isAbsolute(path));

        const options: std.Io.Dir.CreateFileAtomicOptions = .{
            .make_path = true,
            .replace = false,
        };

        var atomic = std.Io.Dir.cwd().createFileAtomic(config.io, path, options) catch {
            return error.WriteFailed;
        };

        defer atomic.deinit(config.io);

        var buffer: [write_bytes_max]u8 = undefined;
        var sink = atomic.file.writer(config.io, &buffer);
        var writer: toml.Writer = undefined;

        writer.init(&sink.interface, writer_options);

        toml.encode(TomlConfig, &writer, settings) catch |err| switch (err) {
            error.DatetimeInvalid, error.Utf8Invalid => return error.ContentInvalid,
            error.WriteFailed => return error.WriteFailed,
        };

        writer.finish();

        sink.interface.flush() catch {
            return error.WriteFailed;
        };

        atomic.file.sync(config.io) catch {
            return error.WriteFailed;
        };

        atomic.link(config.io) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return error.WriteFailed,
        };
    }

    fn default_lock_shortcut() Shortcut {
        const combination = Combination{
            .modifier_set = Modifier.from(.{ .ctrl = true, .alt = true }),
            .value = .l,
        };

        return Shortcut{ .combination = combination };
    }

    fn default_unlock_shortcut() Shortcut {
        const sequence = comptime Sequence.init("UNLOCK") catch {
            @compileError("locker: invalid default unlock sequence");
        };

        return Shortcut{ .sequence = sequence };
    }

    fn join(buffer: []u8, directory: []const u8, name: []const u8) CapacityError![]const u8 {
        assert(directory.len > 0);
        assert(name.len > 0);

        const result = std.mem.print(
            buffer,
            "{s}{c}{s}",
            .{ directory, std.Io.Dir.path.sep, name },
        ) catch {
            return error.PathTooLong;
        };

        assert(result.len == directory.len + 1 + name.len);

        return result;
    }

    fn parse_combination(source: *const TomlCombination) SettingsError!Combination {
        var combination = Combination{};

        if (source.modifiers) |array| {
            combination.modifier_set = parse_modifier_array(array);
        }

        combination.value = try parse_key(source.key);

        assert(combination.is_valid());

        return combination;
    }

    fn parse_disabled_array(
        array: []const TomlCombination,
        target: *[disabled_count_max]Combination,
    ) ParseError!u32 {
        if (array.len > disabled_count_max) {
            return error.DisablesExhausted;
        }

        var count: u32 = 0;

        for (array) |*item| {
            assert(count < disabled_count_max);

            target[count] = try parse_combination(item);
            count += 1;
        }

        assert(count == array.len);

        return count;
    }

    fn parse_key(text: []const u8) SettingsError!Keycode {
        const value = Keycode.from_string(text) orelse return error.KeyInvalid;

        assert(value != .silent);

        return value;
    }

    fn parse_modifier_array(array: []const []const u8) Modifier {
        var result = Modifier{};

        for (array) |item| {
            if (Modifier.Kind.from_string(item)) |kind| {
                result.flags |= kind.to_flag();
            }
        }

        return result;
    }

    fn parse_remap_array(
        array: []const TomlRemap,
        target: *[remap_count_max]RemapRule,
    ) ParseError!u32 {
        if (array.len > remap_count_max) {
            return error.RemapsExhausted;
        }

        var count: u32 = 0;

        for (array) |*item| {
            assert(count < remap_count_max);

            target[count] = .{
                .from = try parse_combination(&item.from),
                .to = try parse_combination(&item.to),
            };

            assert(target[count].is_valid());

            count += 1;
        }

        assert(count == array.len);

        return count;
    }

    fn parse_shortcut(shortcut: *const TomlShortcut) ParseError!Shortcut {
        if (shortcut.sequence) |sequence| {
            return Shortcut{ .sequence = try Sequence.init(sequence) };
        }

        var combination = Combination{};

        if (shortcut.modifiers) |array| {
            combination.modifier_set = parse_modifier_array(array);
        }

        const text = shortcut.key orelse return error.KeyMissing;

        combination.value = try parse_key(text);

        return Shortcut{ .combination = combination };
    }
};

const testing = std.testing;

const sample =
    \\is_keyboard_locked = true
    \\is_mouse_locked = false
    \\show_notification = true
    \\
    \\[lock]
    \\key = "l"
    \\modifiers = ["ctrl", "alt"]
    \\
    \\[unlock]
    \\sequence = "UNLOCK"
    \\
    \\[[disabled]]
    \\key = "e"
    \\modifiers = ["win"]
    \\
    \\[[remap]]
    \\from = { key = "q", modifiers = ["win"] }
    \\to = { key = "f4", modifiers = ["alt"] }
;

const default_text =
    \\is_keyboard_locked = true
    \\is_mouse_locked = false
    \\show_notification = true
    \\
    \\[lock]
    \\key = "L"
    \\modifiers = ["ctrl", "alt"]
    \\
    \\[unlock]
    \\sequence = "UNLOCK"
    \\
;

const legacy_default =
    \\.{
    \\    .disabled = null,
    \\    .is_keyboard_locked = true,
    \\    .is_mouse_locked = false,
    \\    .lock = .{
    \\        .key = "L",
    \\        .modifiers = .{ "ctrl", "alt" },
    \\        .sequence = null,
    \\    },
    \\    .remap = null,
    \\    .show_notification = true,
    \\    .unlock = .{
    \\        .key = null,
    \\        .modifiers = null,
    \\        .sequence = "UNLOCK",
    \\    },
    \\}
;

fn absolute_path_of(directory: *const testing.TmpDir, buffer: []u8) ![]const u8 {
    const length = try directory.dir.realPath(testing.io, buffer);
    return buffer[0..length];
}

fn expect_config_equal(expected: *const Config, actual: *const Config) !void {
    try testing.expectEqual(expected.is_keyboard_locked, actual.is_keyboard_locked);
    try testing.expectEqual(expected.is_mouse_locked, actual.is_mouse_locked);
    try testing.expectEqual(expected.show_notification, actual.show_notification);
    try testing.expectEqualDeep(expected.lock_shortcut, actual.lock_shortcut);
    try testing.expectEqualDeep(expected.unlock_shortcut, actual.unlock_shortcut);
    try testing.expectEqual(expected.disabled_count, actual.disabled_count);
    try testing.expectEqual(expected.remap_count, actual.remap_count);

    const disabled_count = expected.disabled_count;
    const remap_count = expected.remap_count;

    try testing.expectEqualDeep(
        expected.disabled[0..disabled_count],
        actual.disabled[0..disabled_count],
    );

    try testing.expectEqualDeep(expected.remap[0..remap_count], actual.remap[0..remap_count]);
}

fn expect_legacy_kept(expected: anyerror, legacy: []const u8) !void {
    var directory = testing.tmpDir(.{});
    defer directory.cleanup();

    try directory.dir.writeFile(testing.io, .{ .sub_path = file_name_legacy, .data = legacy });

    var buffer: [umbra.limits.path_bytes_max]u8 = undefined;
    const absolute = try absolute_path_of(&directory, &buffer);
    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    try testing.expectError(expected, fixture.load_from(absolute));
    try testing.expectError(error.FileNotFound, directory.dir.access(testing.io, file_name, .{}));
    try testing.expect(std.mem.endsWith(u8, fixture.get_path().?, file_name_legacy));
    try testing.expect(fixture.diagnostic == null);
    try testing.expectEqual(Keycode.l, fixture.lock_shortcut.combination.value);

    var source: [write_bytes_max]u8 = undefined;
    const kept = try directory.dir.readFile(testing.io, file_name_legacy, &source);

    try testing.expectEqualStrings(legacy, kept);

    try directory.dir.writeFile(testing.io, .{
        .sub_path = file_name_legacy,
        .data = ".{ .is_mouse_locked = true }",
    });

    try fixture.reload();

    try testing.expect(fixture.is_mouse_locked);
    try testing.expectError(error.FileNotFound, directory.dir.access(testing.io, file_name, .{}));
}

fn expect_rejected(expected: anyerror, content: []const u8) !void {
    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    try testing.expectError(expected, fixture.parse(content));
    try testing.expectEqual(@as(u32, 0), fixture.remap_count);
    try testing.expectEqual(@as(u32, 0), fixture.disabled_count);
}

test Config {
    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    try fixture.parse(sample);

    const win = Modifier.from(.{ .win = true });
    const explorer = Key{ .value = .e, .down = true, .modifiers = win };
    const quit = Key{ .value = .q, .down = true, .modifiers = win };

    try testing.expect(fixture.is_disabled(&explorer));
    try testing.expect(!fixture.is_disabled(&quit));

    const rule = fixture.remap_for(&quit) orelse return error.RuleMissing;

    try testing.expectEqual(Keycode.f4, rule.to.value);
    try testing.expect(rule.to.modifier_set.alt());
    try testing.expect(fixture.remap_for(&explorer) == null);
    try testing.expectEqualStrings("UNLOCK", fixture.unlock_shortcut.sequence.to_slice());
    try testing.expectEqual(Keycode.l, fixture.lock_shortcut.combination.value);
}

test "the written default parses back to the initial configuration" {
    var buffer: [write_bytes_max]u8 = undefined;
    var sink: std.Io.Writer = .fixed(&buffer);
    var writer: toml.Writer = undefined;

    writer.init(&sink, writer_options);

    try toml.encode(TomlConfig, &writer, &default_toml);

    writer.finish();

    const expected = try testing.allocator.create(Config);
    defer testing.allocator.destroy(expected);

    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    expected.init(testing.io);
    fixture.init(testing.io);

    try fixture.parse(sink.buffered());
    try expect_config_equal(expected, fixture);
    try testing.expectEqualStrings(default_text, sink.buffered());
}

test "a fresh start writes the default file and loads it as the default configuration" {
    var directory = testing.tmpDir(.{});
    defer directory.cleanup();

    var buffer: [umbra.limits.path_bytes_max]u8 = undefined;
    const absolute = try absolute_path_of(&directory, &buffer);
    const expected = try testing.allocator.create(Config);
    defer testing.allocator.destroy(expected);

    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    expected.init(testing.io);
    fixture.init(testing.io);

    try fixture.load_from(absolute);
    try expect_config_equal(expected, fixture);

    var source: [write_bytes_max]u8 = undefined;
    const written = try directory.dir.readFile(testing.io, file_name, &source);
    const legacy = directory.dir.access(testing.io, file_name_legacy, .{});

    try testing.expectEqualStrings(default_text, written);
    try testing.expectError(error.FileNotFound, legacy);
    try testing.expect(std.mem.endsWith(u8, fixture.get_path().?, file_name));
}

test "a full configuration survives an encode and a decode through TOML text" {
    const original = TomlConfig{
        .disabled = &.{
            .{ .key = "e", .modifiers = &.{"win"} },
            .{ .key = "r" },
        },
        .is_keyboard_locked = false,
        .is_mouse_locked = true,
        .lock = .{ .key = "k", .modifiers = &.{ "ctrl", "shift" } },
        .remap = &.{
            .{
                .from = .{ .key = "q", .modifiers = &.{"win"} },
                .to = .{ .key = "f4", .modifiers = &.{"alt"} },
            },
        },
        .show_notification = false,
        .unlock = .{ .sequence = "OPEN" },
    };

    var buffer: [write_bytes_max]u8 = undefined;
    var sink: std.Io.Writer = .fixed(&buffer);
    var writer: toml.Writer = undefined;

    writer.init(&sink, writer_options);

    try toml.encode(TomlConfig, &writer, &original);

    writer.finish();

    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    const decoded = try fixture.parse_toml(sink.buffered());

    try testing.expectEqualDeep(original, decoded);

    try fixture.parse(sink.buffered());

    try testing.expect(!fixture.is_keyboard_locked);
    try testing.expect(fixture.is_mouse_locked);
    try testing.expect(!fixture.show_notification);
    try testing.expectEqual(Keycode.k, fixture.lock_shortcut.combination.value);
    try testing.expect(fixture.lock_shortcut.combination.modifier_set.shift());
    try testing.expectEqualStrings("OPEN", fixture.unlock_shortcut.sequence.to_slice());
    try testing.expectEqual(@as(u32, 2), fixture.disabled_count);
    try testing.expectEqual(Keycode.r, fixture.disabled[1].value);
    try testing.expectEqual(@as(u32, 1), fixture.remap_count);
    try testing.expectEqual(Keycode.f4, fixture.remap[0].to.value);
}

test "a legacy default ZON file migrates to TOML once and the TOML file wins after" {
    var directory = testing.tmpDir(.{});
    defer directory.cleanup();

    try directory.dir.writeFile(testing.io, .{
        .sub_path = file_name_legacy,
        .data = legacy_default,
    });

    var buffer: [umbra.limits.path_bytes_max]u8 = undefined;
    const absolute = try absolute_path_of(&directory, &buffer);
    const expected = try testing.allocator.create(Config);
    defer testing.allocator.destroy(expected);

    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    expected.init(testing.io);

    try expected.apply(&try expected.parse_legacy(legacy_default));

    fixture.init(testing.io);

    try fixture.load_from(absolute);
    try expect_config_equal(expected, fixture);

    var source: [write_bytes_max]u8 = undefined;
    var written: [write_bytes_max]u8 = undefined;

    try testing.expectEqualStrings(
        legacy_default,
        try directory.dir.readFile(testing.io, file_name_legacy, &source),
    );

    try testing.expectEqualStrings(
        default_text,
        try directory.dir.readFile(testing.io, file_name, &written),
    );

    try directory.dir.writeFile(testing.io, .{
        .sub_path = file_name,
        .data = "is_mouse_locked = true\n",
    });

    try fixture.load_from(absolute);

    try testing.expect(fixture.is_mouse_locked);
    try testing.expectEqualDeep(expected.unlock_shortcut, fixture.unlock_shortcut);

    try testing.expectEqualStrings(
        legacy_default,
        try directory.dir.readFile(testing.io, file_name_legacy, &source),
    );
}

test "a legacy ZON file that fails to load stays in use and nothing is written" {
    try expect_legacy_kept(error.ContentInvalid, "not zon");
    try expect_legacy_kept(error.KeyInvalid, ".{ .lock = .{ .key = \"f99\" } }");
}

test "a rejected configuration names whose fault it is and changes nothing" {
    try expect_rejected(error.ContentInvalid, "not toml at all");
    try expect_rejected(error.KeyInvalid, "lock = { key = \"f99\" }");
    try expect_rejected(error.KeyMissing, "lock = { modifiers = [\"ctrl\"] }");
    try expect_rejected(error.SequenceEmpty, "unlock = { sequence = \"\" }");
    try expect_rejected(error.SequenceTooLong, "unlock = { sequence = \"UNLOCKNOW\" }");
    try expect_rejected(error.CharacterInvalid, "unlock = { sequence = \"UN1OCK\" }");
    try expect_rejected(error.ContentInvalid, "[[remap]]\nfrom = { key = \"q\" }\n");
}

test "a malformed file names the line, the column, and the reason" {
    const malformed = "[lock]\nkey = \"l\"\nkey = \"k\"\n";

    var directory = testing.tmpDir(.{});
    defer directory.cleanup();

    try directory.dir.writeFile(testing.io, .{ .sub_path = file_name, .data = malformed });

    var buffer: [umbra.limits.path_bytes_max]u8 = undefined;
    const absolute = try absolute_path_of(&directory, &buffer);
    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    try testing.expectError(error.ContentInvalid, fixture.load_from(absolute));

    var source: [write_bytes_max]u8 = undefined;
    const kept = try directory.dir.readFile(testing.io, file_name, &source);

    try testing.expectEqualStrings(malformed, kept);

    const syntax = fixture.diagnostic orelse return error.DiagnosticMissing;

    try testing.expectEqual(@as(u32, 3), syntax.position.line);
    try testing.expectEqual(@as(u32, 1), syntax.position.column);
    try testing.expectEqualStrings("duplicate key", syntax.reason);

    const mismatch = fixture.parse(
        \\is_keyboard_locked = false
        \\
        \\[lock]
        \\key = "l"
        \\modifiers = "ctrl"
    );

    try testing.expectError(error.ContentInvalid, mismatch);

    const kind = fixture.diagnostic orelse return error.DiagnosticMissing;

    try testing.expectEqual(@as(u32, 5), kind.position.line);
    try testing.expectEqual(@as(u32, 13), kind.position.column);
    try testing.expectEqualStrings("the value does not match the field's type", kind.reason);
    try testing.expect(fixture.is_keyboard_locked);

    try fixture.parse("is_keyboard_locked = false\n");

    try testing.expect(fixture.diagnostic == null);
    try testing.expect(!fixture.is_keyboard_locked);

    const unknown = fixture.parse("[lock]\nkey = \"l\"\nmodifier = [\"ctrl\"]\n");

    try testing.expectError(error.ContentInvalid, unknown);

    const member = fixture.diagnostic orelse return error.DiagnosticMissing;
    const expected: toml.Position = .{ .column = 1, .line = 3, .offset = 17 };

    try testing.expectEqual(expected, member.position);
    try testing.expectEqualStrings("unknown key", member.reason);
    try testing.expect(!fixture.is_keyboard_locked);
}

test "a key or modifier name longer than any name is rejected rather than trusted" {
    const content =
        \\[lock]
        \\key = "a-key-name-far-longer-than-any-name-nimble-knows"
        \\modifiers = ["a-modifier-name-longer-than-sixteen-bytes"]
    ;

    try expect_rejected(error.KeyInvalid, content);
}

test "more disables than the table holds exhausts it" {
    var buffer: [content_bytes_max]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);

    for (0..disabled_count_max + 1) |_| {
        try writer.writeAll("[[disabled]]\nkey = \"a\"\n");
    }

    try expect_rejected(error.DisablesExhausted, writer.buffered());
}

test "the largest configuration the tables hold fits the document" {
    const modifiers = "modifiers = [\"ctrl\", \"alt\", \"shift\", \"win\"]";
    const combination = "{ key = \"a\", " ++ modifiers ++ " }";
    const disabled = "[[disabled]]\nkey = \"a\"\n" ++ modifiers ++ "\n";
    const remap = "[[remap]]\nfrom = " ++ combination ++ "\nto = " ++ combination ++ "\n";
    const shortcut = "{ key = \"a\", " ++ modifiers ++ ", sequence = \"OPEN\" }";

    var buffer: [content_bytes_max]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);

    try writer.writeAll("is_keyboard_locked = true\nis_mouse_locked = true\n");
    try writer.writeAll("show_notification = false\n");
    try writer.writeAll("lock = " ++ shortcut ++ "\nunlock = " ++ shortcut ++ "\n");

    for (0..disabled_count_max) |_| {
        try writer.writeAll(disabled);
    }

    for (0..remap_count_max) |_| {
        try writer.writeAll(remap);
    }

    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    try fixture.parse(writer.buffered());

    try testing.expectEqual(disabled_count_max, fixture.disabled_count);
    try testing.expectEqual(remap_count_max, fixture.remap_count);
    try testing.expectEqualStrings("OPEN", fixture.unlock_shortcut.sequence.to_slice());
    try testing.expect(fixture.is_mouse_locked);
    try testing.expect(!fixture.show_notification);
}

test "a sequence uppercases its source" {
    const sequence = try Config.Sequence.init("unlock");

    try testing.expect(sequence.is_valid());
    try testing.expectEqualStrings("UNLOCK", sequence.to_slice());
}

test "a combination matches only its exact key and modifiers" {
    const combination = Config.Combination{
        .modifier_set = Modifier.from(.{ .ctrl = true }),
        .value = .l,
    };

    const exact = Key{
        .value = .l,
        .down = true,
        .modifiers = Modifier.from(.{ .ctrl = true }),
    };

    const wrong_key = Key{
        .value = .k,
        .down = true,
        .modifiers = Modifier.from(.{ .ctrl = true }),
    };

    const wrong_modifiers = Key{ .value = .l, .down = true };

    try testing.expect(combination.match(&exact));
    try testing.expect(!combination.match(&wrong_key));
    try testing.expect(!combination.match(&wrong_modifiers));
}

test "a fresh configuration carries usable defaults and no path" {
    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    try testing.expect(fixture.lock_shortcut.combination.is_valid());
    try testing.expect(fixture.unlock_shortcut.sequence.is_valid());
    try testing.expect(fixture.get_path() == null);
    try testing.expectError(error.FileMissing, fixture.reload());
}
