const std = @import("std");

const nimble = @import("nimble");
const wisp = @import("wisp");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const keycode = nimble.keycode;
const modifier = nimble.modifier;

const Key = nimble.Key;
const Keycode = nimble.Keycode;

pub const Error = error{
    InvalidKey,
    ParseError,
    SequenceTooLong,
    TooManyDisabled,
    TooManyRemap,
};

pub const ShortcutKind = enum(u8) {
    combination = 0,
    sequence = 1,
};

pub const Combination = struct {
    modifier_set: modifier.Set = .{},
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

pub const Sequence = struct {
    pub const length_max: u32 = 32;

    data: [length_max]u8 = [_]u8{0} ** length_max,
    length: u32 = 0,

    pub fn init(source: []const u8) Error!Sequence {
        if (source.len == 0) {
            return Error.InvalidKey;
        }

        if (source.len > length_max) {
            return Error.SequenceTooLong;
        }

        var result = Sequence{};
        const source_length: u32 = @intCast(source.len);

        for (0..source_length) |index| {
            result.data[index] = std.ascii.toUpper(source[index]);
        }

        result.length = source_length;

        return result;
    }

    pub fn is_valid(sequence: *const Sequence) bool {
        return sequence.length > 0 and sequence.length <= length_max;
    }

    pub fn to_slice(sequence: *const Sequence) []const u8 {
        assert(sequence.is_valid());

        return sequence.data[0..sequence.length];
    }
};

pub const Shortcut = union(ShortcutKind) {
    combination: Combination,
    sequence: Sequence,
};

pub const RemapRule = struct {
    from: Combination,
    to: Combination,

    pub fn is_valid(rule: *const RemapRule) bool {
        return rule.from.is_valid() and rule.to.is_valid();
    }
};

const ZonShortcut = struct {
    key: ?[]const u8 = null,
    modifiers: ?[]const []const u8 = null,
    sequence: ?[]const u8 = null,
};

const ZonCombination = struct {
    key: []const u8,
    modifiers: ?[]const []const u8 = null,
};

const ZonRemap = struct {
    from: ZonCombination,
    to: ZonCombination,
};

const ZonConfig = struct {
    disabled: ?[]const ZonCombination = null,
    is_keyboard_locked: bool = true,
    is_mouse_locked: bool = false,
    lock: ?ZonShortcut = null,
    remap: ?[]const ZonRemap = null,
    show_notification: bool = true,
    unlock: ?ZonShortcut = null,
};

pub const Config = struct {
    pub const arena_size: u32 = 1024 * 128;
    pub const content_length_max: u32 = 1024 * 64;
    pub const disabled_count_max: u32 = 64;
    pub const path_length_max: u32 = 512;
    pub const remap_count_max: u32 = 64;

    arena: std.heap.FixedBufferAllocator = undefined,
    arena_buffer: *[arena_size]u8 = undefined,
    config_path: [path_length_max]u8 = [_]u8{0} ** path_length_max,
    config_path_length: u32 = 0,
    content_buffer: *[content_length_max + 1]u8 = undefined,
    disabled_count: u32 = 0,
    disabled_entry: [disabled_count_max]Combination = [_]Combination{.{}} ** disabled_count_max,
    io: std.Io,
    is_keyboard_locked: bool = true,
    is_loaded_from_file: bool = false,
    is_mouse_locked: bool = false,
    lock_shortcut: Shortcut,
    remap_count: u32 = 0,
    remap_entry: [remap_count_max]RemapRule = @splat(.{ .from = .{}, .to = .{} }),
    show_notification: bool = true,
    unlock_shortcut: Shortcut,

    pub fn init(io: std.Io) Config {
        const gpa = std.heap.page_allocator;

        const arena_buffer = gpa.create([arena_size]u8) catch {
            @panic("Failed to allocate arena buffer");
        };

        const content_buffer = gpa.create([content_length_max + 1]u8) catch {
            @panic("Failed to allocate content buffer");
        };

        var result = Config{
            .lock_shortcut = default_lock_shortcut(),
            .unlock_shortcut = default_unlock_shortcut(),
            .arena_buffer = arena_buffer,
            .content_buffer = content_buffer,
            .io = io,
        };

        result.arena = std.heap.FixedBufferAllocator.init(result.arena_buffer);

        return result;
    }

    pub fn deinit(config: *Config) void {
        config.arena.reset();
        std.heap.page_allocator.destroy(config.arena_buffer);
        std.heap.page_allocator.destroy(config.content_buffer);
    }

    pub fn find_remap_entry(config: *const Config, key: *const Key) ?RemapRule {
        const slice = config.get_remap();

        for (slice) |entry| {
            if (entry.from.match(key)) {
                return entry;
            }
        }

        return null;
    }

    pub fn get_config_path(config: *const Config) ?[]const u8 {
        if (config.config_path_length == 0) {
            return null;
        }

        assert(config.config_path_length <= path_length_max);

        return config.config_path[0..config.config_path_length];
    }

    pub fn get_disabled(config: *const Config) []const Combination {
        assert(config.disabled_count <= disabled_count_max);

        return config.disabled_entry[0..config.disabled_count];
    }

    pub fn get_remap(config: *const Config) []const RemapRule {
        assert(config.remap_count <= remap_count_max);

        return config.remap_entry[0..config.remap_count];
    }

    pub fn is_disabled(config: *const Config, key: *const Key) bool {
        const slice = config.get_disabled();

        for (slice) |entry| {
            if (entry.match(key)) {
                return true;
            }
        }

        return false;
    }

    pub fn load(io: std.Io) Config {
        var config = Config.init(io);

        if (!config.load_config_path()) {
            return config;
        }

        if (!config.load_from_file()) {
            return config;
        }

        return config;
    }

    pub fn parse(config: *Config, content: [:0]const u8) Error!void {
        assert(content.len > 0);

        config.arena.reset();

        const arena = config.arena.allocator();

        const parsed = std.zon.parse.fromSliceAlloc(
            ZonConfig,
            arena,
            content,
            null,
            .{},
        ) catch {
            return Error.ParseError;
        };

        var lock_shortcut = default_lock_shortcut();
        var unlock_shortcut = default_unlock_shortcut();

        if (parsed.lock) |lock| {
            lock_shortcut = try parse_shortcut(&lock);
        }

        if (parsed.unlock) |unlock| {
            unlock_shortcut = try parse_shortcut(&unlock);
        }

        var staged_remap: [remap_count_max]RemapRule = undefined;
        var staged_remap_count: u32 = 0;

        if (parsed.remap) |array| {
            staged_remap_count = try parse_remap_array(array, &staged_remap);
        }

        var staged_disabled: [disabled_count_max]Combination = undefined;
        var staged_disabled_count: u32 = 0;

        if (parsed.disabled) |array| {
            staged_disabled_count = try parse_disabled_array(array, &staged_disabled);
        }

        config.is_keyboard_locked = parsed.is_keyboard_locked;
        config.is_mouse_locked = parsed.is_mouse_locked;
        config.show_notification = parsed.show_notification;
        config.lock_shortcut = lock_shortcut;
        config.unlock_shortcut = unlock_shortcut;
        config.remap_entry = staged_remap;
        config.remap_count = staged_remap_count;
        config.disabled_entry = staged_disabled;
        config.disabled_count = staged_disabled_count;

        assert(config.remap_count <= remap_count_max);
        assert(config.disabled_count <= disabled_count_max);
    }

    pub fn reset(config: *Config) void {
        config.arena.reset();
        config.remap_count = 0;
        config.disabled_count = 0;

        config.lock_shortcut = default_lock_shortcut();
        config.unlock_shortcut = default_unlock_shortcut();
        config.is_keyboard_locked = true;
        config.is_mouse_locked = false;
        config.show_notification = true;
    }

    pub fn save(config: *Config) void {
        if (!config.is_loaded_from_file) {
            return;
        }

        const path = config.config_path[0..config.config_path_length];
        const directory = std.fs.path.dirname(path) orelse return;

        std.Io.Dir.cwd().createDirPath(config.io, directory) catch {
            return;
        };

        config.write_config_file(path);
    }

    fn load_config_path(config: *Config) bool {
        var buffer: [path_length_max]u8 = undefined;

        const base = wisp.paths.config_dir(&buffer, "locker") catch {
            return false;
        };

        const full_path = std.fmt.bufPrint(
            &config.config_path,
            "{s}{c}{s}",
            .{ base, std.fs.path.sep, "config.zon" },
        ) catch {
            return false;
        };

        config.config_path_length = @intCast(full_path.len);

        return true;
    }

    fn load_from_file(config: *Config) bool {
        assert(config.config_path_length > 0);

        const path = config.config_path[0..config.config_path_length];

        const file = std.Io.Dir.openFileAbsolute(config.io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                config.is_loaded_from_file = true;
                config.save();

                return true;
            },
            else => return false,
        };

        defer file.close(config.io);

        const count = file.readPositionalAll(
            config.io,
            config.content_buffer[0..content_length_max],
            0,
        ) catch {
            return false;
        };

        if (count == 0) {
            return false;
        }

        config.content_buffer[count] = 0;

        const slice: [:0]const u8 = config.content_buffer[0..count :0];

        config.parse(slice) catch {
            return false;
        };

        config.is_loaded_from_file = true;

        return true;
    }

    fn parse_disabled_array(
        array: []const ZonCombination,
        target: *[disabled_count_max]Combination,
    ) Error!u32 {
        const length: u32 = @intCast(array.len);

        if (length > disabled_count_max) {
            return Error.TooManyDisabled;
        }

        var count: u32 = 0;

        for (array) |item| {
            assert(count < disabled_count_max);

            const combination = try parse_zon_combination(&item);

            target[count] = combination;
            count += 1;
        }

        assert(count == length);

        return count;
    }

    fn parse_remap_array(array: []const ZonRemap, target: *[remap_count_max]RemapRule) Error!u32 {
        const length: u32 = @intCast(array.len);

        if (length > remap_count_max) {
            return Error.TooManyRemap;
        }

        var count: u32 = 0;

        for (array) |item| {
            assert(count < remap_count_max);

            const from = try parse_zon_combination(&item.from);
            const to = try parse_zon_combination(&item.to);

            target[count] = .{ .from = from, .to = to };
            count += 1;
        }

        assert(count == length);

        return count;
    }

    fn to_zon_config(config: *Config) !ZonConfig {
        const arena = config.arena.allocator();

        return ZonConfig{
            .is_keyboard_locked = config.is_keyboard_locked,
            .is_mouse_locked = config.is_mouse_locked,
            .show_notification = config.show_notification,
            .lock = try shortcut_to_zon(arena, &config.lock_shortcut),
            .unlock = try shortcut_to_zon(arena, &config.unlock_shortcut),
            .remap = try config.build_zon_remap(arena),
            .disabled = try config.build_zon_disabled(arena),
        };
    }

    fn build_zon_disabled(config: *Config, arena: Allocator) !?[]const ZonCombination {
        if (config.disabled_count == 0) {
            return null;
        }

        const slice = try arena.alloc(ZonCombination, config.disabled_count);

        for (0..config.disabled_count) |index| {
            assert(config.disabled_entry[index].is_valid());

            slice[index] = try combination_to_zon(arena, &config.disabled_entry[index]);
        }

        return slice;
    }

    fn build_zon_remap(config: *Config, arena: Allocator) !?[]const ZonRemap {
        if (config.remap_count == 0) {
            return null;
        }

        const slice = try arena.alloc(ZonRemap, config.remap_count);

        for (0..config.remap_count) |index| {
            const entry = config.remap_entry[index];

            assert(entry.is_valid());

            slice[index] = .{
                .from = try combination_to_zon(arena, &entry.from),
                .to = try combination_to_zon(arena, &entry.to),
            };
        }

        return slice;
    }

    fn write_config_file(config: *Config, path: []const u8) void {
        const file = std.Io.Dir.createFileAbsolute(config.io, path, .{}) catch {
            return;
        };

        defer file.close(config.io);

        var buffer: [4096]u8 = undefined;
        var writer = file.writer(config.io, &buffer);

        const zon = config.to_zon_config() catch {
            return;
        };

        std.zon.stringify.serialize(zon, .{}, &writer.interface) catch {
            return;
        };

        writer.interface.flush() catch {
            return;
        };
    }
};

fn default_lock_shortcut() Shortcut {
    const combination = Combination{
        .modifier_set = modifier.Set.from(.{ .ctrl = true, .alt = true }),
        .value = .l,
    };

    return Shortcut{ .combination = combination };
}

fn default_unlock_shortcut() Shortcut {
    const sequence = Sequence.init("UNLOCK") catch {
        @panic("Failed to initialize default unlock sequence");
    };

    return Shortcut{ .sequence = sequence };
}

fn keycode_to_string(arena: Allocator, value: Keycode) !?[]const u8 {
    assert(value != .silent);

    if (value.to_char()) |character| {
        const buffer = try arena.alloc(u8, 1);

        buffer[0] = character;

        return buffer;
    }

    return value.to_string();
}

fn combination_to_zon(
    arena: Allocator,
    combination: *const Combination,
) !ZonCombination {
    assert(combination.is_valid());

    const string = try keycode_to_string(arena, combination.value) orelse {
        return Error.InvalidKey;
    };

    return ZonCombination{
        .modifiers = try modifier_set_to_string(arena, &combination.modifier_set),
        .key = string,
    };
}

fn modifier_set_to_string(
    arena: Allocator,
    modifier_set: *const modifier.Set,
) !?[]const []const u8 {
    const array = modifier_set.to_array();
    var count: u8 = 0;

    for (0..modifier.kind_count) |kind_index| {
        if (array[kind_index] != null) {
            count += 1;
        }
    }

    if (count == 0) {
        return null;
    }

    const result = try arena.alloc([]const u8, count);
    var result_index: u8 = 0;

    for (0..modifier.kind_count) |kind_index| {
        if (array[kind_index]) |modifier_kind| {
            result[result_index] = @tagName(modifier_kind);
            result_index += 1;
        }
    }

    return result;
}

fn parse_modifier_array(array: []const []const u8) Error!modifier.Set {
    var result = modifier.Set{};

    for (array) |item| {
        if (modifier.Kind.from_string(item)) |kind| {
            result.flags |= kind.to_flag();
        }
    }

    return result;
}

fn parse_shortcut(shortcut: *const ZonShortcut) Error!Shortcut {
    if (shortcut.sequence) |sequence| {
        const parsed_sequence = try Sequence.init(sequence);

        return Shortcut{ .sequence = parsed_sequence };
    }

    var combination = Combination{};

    if (shortcut.modifiers) |array| {
        combination.modifier_set = try parse_modifier_array(array);
    }

    if (shortcut.key) |string| {
        combination.value = keycode.Keycode.from_string(string) orelse {
            return Error.InvalidKey;
        };
    } else {
        return Error.InvalidKey;
    }

    return Shortcut{ .combination = combination };
}

fn parse_zon_combination(zon: *const ZonCombination) Error!Combination {
    var combination = Combination{};

    if (zon.modifiers) |array| {
        combination.modifier_set = try parse_modifier_array(array);
    }

    combination.value = keycode.Keycode.from_string(zon.key) orelse {
        return Error.InvalidKey;
    };

    return combination;
}

fn shortcut_to_zon(arena: Allocator, shortcut: *const Shortcut) !ZonShortcut {
    switch (shortcut.*) {
        .combination => |combination| {
            assert(combination.is_valid());

            return ZonShortcut{
                .modifiers = try modifier_set_to_string(arena, &combination.modifier_set),
                .key = try keycode_to_string(arena, combination.value),
            };
        },
        .sequence => |sequence| {
            assert(sequence.is_valid());

            const slice = sequence.to_slice();
            const copy = try arena.alloc(u8, slice.len);

            @memcpy(copy, slice);

            return ZonShortcut{
                .sequence = copy,
            };
        },
    }
}

const testing = std.testing;

test "a sequence uppercases and bounds its source" {
    const sequence = try Sequence.init("unlock");

    try testing.expect(sequence.is_valid());
    try testing.expectEqualStrings("UNLOCK", sequence.to_slice());
}

test "a sequence rejects an empty or oversized source" {
    const long = [_]u8{'a'} ** (Sequence.length_max + 1);

    try testing.expectError(Error.InvalidKey, Sequence.init(""));
    try testing.expectError(Error.SequenceTooLong, Sequence.init(&long));
}

test "a combination matches only its exact key and modifiers" {
    const combination = Combination{
        .modifier_set = modifier.Set.from(.{ .ctrl = true }),
        .value = .l,
    };

    const exact = Key{
        .value = .l,
        .down = true,
        .modifiers = modifier.Set.from(.{ .ctrl = true }),
    };

    const wrong_key = Key{
        .value = .k,
        .down = true,
        .modifiers = modifier.Set.from(.{ .ctrl = true }),
    };

    const wrong_modifiers = Key{ .value = .l, .down = true };

    try testing.expect(combination.match(&exact));
    try testing.expect(!combination.match(&wrong_key));
    try testing.expect(!combination.match(&wrong_modifiers));
}

test "parse_shortcut resolves keys, modifiers, and sequences" {
    const combination = try parse_shortcut(&.{
        .key = "l",
        .modifiers = &.{ "ctrl", "alt" },
    });

    try testing.expectEqual(Keycode.l, combination.combination.value);
    try testing.expect(combination.combination.modifier_set.ctrl());
    try testing.expect(combination.combination.modifier_set.alt());

    const sequence = try parse_shortcut(&.{ .sequence = "unlock" });

    try testing.expectEqualStrings("UNLOCK", sequence.sequence.to_slice());

    try testing.expectError(Error.InvalidKey, parse_shortcut(&.{}));
}

test "the default shortcuts are valid" {
    const lock = default_lock_shortcut();
    const unlock = default_unlock_shortcut();

    try testing.expect(lock.combination.is_valid());
    try testing.expect(unlock.sequence.is_valid());
}
