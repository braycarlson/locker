const std = @import("std");

const nimble = @import("nimble");

const keycode = nimble.keycode;
const modifier = nimble.modifier;
const path_util = @import("path.zig");

pub const Error = error{
    BufferTooSmall,
    InvalidKey,
    InvalidModifier,
    InvalidPath,
    InvalidShortcut,
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
    value: u8 = 0,

    pub fn is_valid(self: *const Combination) bool {
        return keycode.is_valid(self.value);
    }

    pub fn match(self: *const Combination, value: u8, current: *const modifier.Set) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(value));

        if (self.value != value) {
            return false;
        }

        return self.modifier_set.eql(current);
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

        for (0..source_length) |i| {
            result.data[i] = to_virtual_key(source[i]);
        }

        result.length = source_length;

        return result;
    }

    pub fn is_valid(self: *const Sequence) bool {
        return self.length > 0 and self.length <= length_max;
    }

    pub fn to_slice(self: *const Sequence) []const u8 {
        std.debug.assert(self.is_valid());
        return self.data[0..self.length];
    }

    fn to_virtual_key(character: u8) u8 {
        if (character >= 'a' and character <= 'z') {
            return character - 32;
        }
        return character;
    }
};

pub const Shortcut = union(ShortcutKind) {
    combination: Combination,
    sequence: Sequence,
};

pub const Remap = struct {
    from: Combination,
    to: Combination,

    pub fn is_valid(self: *const Remap) bool {
        return self.from.is_valid() and self.to.is_valid();
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
    pub const sequence_buffer_length_max: u32 = 8;

    arena: std.heap.FixedBufferAllocator = undefined,
    arena_buffer: *[arena_size]u8 = undefined,
    config_path: [path_length_max]u8 = [_]u8{0} ** path_length_max,
    config_path_length: u32 = 0,
    content_buffer: *[content_length_max + 1]u8 = undefined,
    disabled_count: u32 = 0,
    disabled_entry: [disabled_count_max]Combination = [_]Combination{.{}} ** disabled_count_max,
    is_keyboard_locked: bool = true,
    is_loaded_from_file: bool = false,
    is_mouse_locked: bool = false,
    lock_sequence_buffer: [sequence_buffer_length_max]u8 = [_]u8{0} ** sequence_buffer_length_max,
    lock_sequence_length: u32 = 0,
    lock_shortcut: Shortcut,
    page_allocator: std.mem.Allocator = undefined,
    remap_count: u32 = 0,
    remap_entry: [remap_count_max]Remap = [_]Remap{.{ .from = .{}, .to = .{} }} ** remap_count_max,
    show_notification: bool = true,
    unlock_sequence_buffer: [sequence_buffer_length_max]u8 = [_]u8{0} ** sequence_buffer_length_max,
    unlock_sequence_length: u32 = 0,
    unlock_shortcut: Shortcut,

    pub fn init() Config {
        const default_lock = Combination{
            .modifier_set = modifier.Set.from(.{ .ctrl = true, .alt = true }),
            .value = 'L',
        };

        const default_unlock = Sequence.init("UNLOCK") catch {
            @panic("Failed to initialize default unlock sequence");
        };

        const allocator = std.heap.page_allocator;

        const arena_buf = allocator.create([arena_size]u8) catch {
            @panic("Failed to allocate arena buffer");
        };

        const content_buf = allocator.create([content_length_max + 1]u8) catch {
            @panic("Failed to allocate content buffer");
        };

        var result = Config{
            .lock_shortcut = .{ .combination = default_lock },
            .unlock_shortcut = .{ .sequence = default_unlock },
            .arena_buffer = arena_buf,
            .content_buffer = content_buf,
            .page_allocator = allocator,
        };

        result.arena = std.heap.FixedBufferAllocator.init(result.arena_buffer);

        return result;
    }

    pub fn deinit(self: *Config) void {
        self.arena.reset();
        self.page_allocator.destroy(self.arena_buffer);
        self.page_allocator.destroy(self.content_buffer);
    }

    pub fn find_remap(self: *const Config, value: u8, current: *const modifier.Set) ?Combination {
        std.debug.assert(keycode.is_valid(value));

        const slice = self.get_remap();

        for (slice) |entry| {
            if (entry.from.match(value, current)) {
                return entry.to;
            }
        }

        return null;
    }

    pub fn find_remap_entry(self: *const Config, value: u8, current: *const modifier.Set) ?Remap {
        std.debug.assert(keycode.is_valid(value));

        const slice = self.get_remap();

        for (slice) |entry| {
            if (entry.from.match(value, current)) {
                return entry;
            }
        }

        return null;
    }

    pub fn get_config_path(self: *const Config) ?[]const u8 {
        if (self.config_path_length == 0) {
            return null;
        }

        return self.config_path[0..self.config_path_length];
    }

    pub fn get_disabled(self: *const Config) []const Combination {
        return self.disabled_entry[0..self.disabled_count];
    }

    pub fn get_lock_sequence(self: *Config) ?[]const u8 {
        switch (self.lock_shortcut) {
            .combination => |combination| {
                std.debug.assert(combination.is_valid());

                self.build_combination_sequence(&combination, &self.lock_sequence_buffer, true);

                if (self.lock_sequence_length == 0) {
                    return null;
                }

                return self.lock_sequence_buffer[0..self.lock_sequence_length];
            },
            .sequence => |*sequence| {
                std.debug.assert(sequence.is_valid());
                return sequence.to_slice();
            },
        }
    }

    pub fn get_remap(self: *const Config) []const Remap {
        return self.remap_entry[0..self.remap_count];
    }

    pub fn get_unlock_sequence(self: *Config) ?[]const u8 {
        switch (self.unlock_shortcut) {
            .combination => |combination| {
                std.debug.assert(combination.is_valid());

                self.build_combination_sequence(&combination, &self.unlock_sequence_buffer, false);

                if (self.unlock_sequence_length == 0) {
                    return null;
                }

                return self.unlock_sequence_buffer[0..self.unlock_sequence_length];
            },
            .sequence => |*sequence| {
                std.debug.assert(sequence.is_valid());
                return sequence.to_slice();
            },
        }
    }

    pub fn is_disabled(self: *const Config, value: u8, current: *const modifier.Set) bool {
        std.debug.assert(keycode.is_valid(value));

        const slice = self.get_disabled();

        for (slice) |entry| {
            if (entry.match(value, current)) {
                return true;
            }
        }

        return false;
    }

    pub fn load() !Config {
        var config = Config.init();

        if (!config.load_config_path()) {
            return config;
        }

        if (!config.load_from_file()) {
            return config;
        }

        return config;
    }

    pub fn parse(self: *Config, content: [:0]const u8) !void {
        std.debug.assert(content.len > 0);

        const allocator = self.arena.allocator();

        const parsed = std.zon.parse.fromSlice(ZonConfig, allocator, content, null, .{}) catch {
            return Error.ParseError;
        };

        self.is_keyboard_locked = parsed.is_keyboard_locked;
        self.is_mouse_locked = parsed.is_mouse_locked;
        self.show_notification = parsed.show_notification;

        if (parsed.lock) |lock| {
            self.lock_shortcut = try parse_shortcut(&lock);
        }

        if (parsed.unlock) |unlock| {
            self.unlock_shortcut = try parse_shortcut(&unlock);
        }

        if (parsed.remap) |array| {
            try self.parse_remap_array(array);
        }

        if (parsed.disabled) |array| {
            try self.parse_disabled_array(array);
        }
    }

    pub fn reset(self: *Config) void {
        self.arena.reset();
        self.remap_count = 0;
        self.disabled_count = 0;

        const default_lock = Combination{
            .modifier_set = modifier.Set.from(.{ .ctrl = true, .alt = true }),
            .value = 'L',
        };

        const default_unlock = Sequence.init("UNLOCK") catch {
            @panic("Failed to initialize default unlock sequence");
        };

        self.lock_shortcut = .{ .combination = default_lock };
        self.unlock_shortcut = .{ .sequence = default_unlock };
        self.is_keyboard_locked = true;
        self.is_mouse_locked = false;
        self.show_notification = true;
    }

    pub fn save(self: *Config) !void {
        if (!self.is_loaded_from_file) {
            return;
        }

        const path = self.config_path[0..self.config_path_length];

        path_util.ensure_directory_exists(path) catch {
            return;
        };

        self.write_config_file(path);
    }

    fn build_combination_sequence(
        self: *Config,
        combination: *const Combination,
        buffer: *[sequence_buffer_length_max]u8,
        is_lock: bool,
    ) void {
        std.debug.assert(combination.is_valid());

        var index: u32 = 0;
        const modifier_array = combination.modifier_set.to_array();

        for (0..modifier.kind_count) |i| {
            if (modifier_array[i]) |modifier_kind| {
                buffer[index] = modifier_kind.to_keycode();
                index += 1;
            }
        }

        buffer[index] = combination.value;
        index += 1;

        if (is_lock) {
            self.lock_sequence_length = index;
        } else {
            self.unlock_sequence_length = index;
        }
    }

    fn build_zon_disabled(self: *Config, allocator: std.mem.Allocator) !?[]const ZonCombination {
        if (self.disabled_count == 0) {
            return null;
        }

        const slice = try allocator.alloc(ZonCombination, self.disabled_count);

        for (0..self.disabled_count) |i| {
            std.debug.assert(self.disabled_entry[i].is_valid());
            slice[i] = try combination_to_zon(allocator, &self.disabled_entry[i]);
        }

        return slice;
    }

    fn build_zon_remap(self: *Config, allocator: std.mem.Allocator) !?[]const ZonRemap {
        if (self.remap_count == 0) {
            return null;
        }

        const slice = try allocator.alloc(ZonRemap, self.remap_count);

        for (0..self.remap_count) |i| {
            const entry = self.remap_entry[i];
            std.debug.assert(entry.is_valid());

            slice[i] = .{
                .from = try combination_to_zon(allocator, &entry.from),
                .to = try combination_to_zon(allocator, &entry.to),
            };
        }

        return slice;
    }

    fn load_config_path(self: *Config) bool {
        var buffer: [path_length_max]u8 = undefined;

        const base = path_util.get_appdata_path(&buffer, "locker") catch {
            return false;
        };

        const full_path = path_util.join_path(&self.config_path, base, "config.zon") orelse {
            return false;
        };

        self.config_path_length = @intCast(full_path.len);

        return true;
    }

    fn load_from_file(self: *Config) bool {
        std.debug.assert(self.config_path_length > 0);

        const path = self.config_path[0..self.config_path_length];

        const file = std.fs.openFileAbsolute(path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                self.is_loaded_from_file = true;
                self.save() catch {};
                return true;
            }
            return false;
        };

        defer file.close();

        const count = file.readAll(self.content_buffer[0..content_length_max]) catch {
            return false;
        };

        if (count == 0) {
            return false;
        }

        self.content_buffer[count] = 0;

        const slice: [:0]const u8 = self.content_buffer[0..count :0];

        self.parse(slice) catch {
            return false;
        };

        self.is_loaded_from_file = true;

        return true;
    }

    fn parse_disabled_array(self: *Config, array: []const ZonCombination) !void {
        const length: u32 = @intCast(array.len);

        if (length > disabled_count_max) {
            return Error.TooManyDisabled;
        }

        self.disabled_count = 0;

        for (array) |item| {
            const combination = try parse_zon_combination(&item);
            self.disabled_entry[self.disabled_count] = combination;
            self.disabled_count += 1;
        }
    }

    fn parse_remap_array(self: *Config, array: []const ZonRemap) !void {
        const length: u32 = @intCast(array.len);

        if (length > remap_count_max) {
            return Error.TooManyRemap;
        }

        self.remap_count = 0;

        for (array) |item| {
            const from = try parse_zon_combination(&item.from);
            const to = try parse_zon_combination(&item.to);

            self.remap_entry[self.remap_count] = .{ .from = from, .to = to };
            self.remap_count += 1;
        }
    }

    fn to_zon_config(self: *Config) !ZonConfig {
        const allocator = self.arena.allocator();

        return ZonConfig{
            .is_keyboard_locked = self.is_keyboard_locked,
            .is_mouse_locked = self.is_mouse_locked,
            .show_notification = self.show_notification,
            .lock = try shortcut_to_zon(allocator, &self.lock_shortcut),
            .unlock = try shortcut_to_zon(allocator, &self.unlock_shortcut),
            .remap = try self.build_zon_remap(allocator),
            .disabled = try self.build_zon_disabled(allocator),
        };
    }

    fn write_config_file(self: *Config, path: []const u8) void {
        const file = std.fs.createFileAbsolute(path, .{}) catch {
            return;
        };

        defer file.close();

        var buffer: [4096]u8 = undefined;
        var writer = file.writer(&buffer);

        const zon = self.to_zon_config() catch {
            return;
        };

        std.zon.stringify.serialize(zon, .{}, &writer.interface) catch {
            return;
        };

        writer.interface.flush() catch {};
    }
};

fn keycode_to_string(allocator: std.mem.Allocator, value: u8) !?[]const u8 {
    std.debug.assert(keycode.is_valid(value));

    if ((value >= 'A' and value <= 'Z') or (value >= '0' and value <= '9')) {
        const buffer = try allocator.alloc(u8, 1);
        buffer[0] = value;
        return buffer;
    }

    return keycode.to_string(value);
}

fn combination_to_zon(allocator: std.mem.Allocator, combination: *const Combination) !ZonCombination {
    std.debug.assert(combination.is_valid());

    const string = try keycode_to_string(allocator, combination.value) orelse {
        return Error.InvalidKey;
    };

    return ZonCombination{
        .modifiers = try modifier_set_to_string(allocator, &combination.modifier_set),
        .key = string,
    };
}

fn modifier_set_to_string(allocator: std.mem.Allocator, modifier_set: *const modifier.Set) !?[]const []const u8 {
    const array = modifier_set.to_array();
    var count: u8 = 0;

    for (0..modifier.kind_count) |i| {
        if (array[i] != null) {
            count += 1;
        }
    }

    if (count == 0) {
        return null;
    }

    const result = try allocator.alloc([]const u8, count);
    var result_index: u8 = 0;

    for (0..modifier.kind_count) |i| {
        if (array[i]) |modifier_kind| {
            result[result_index] = @tagName(modifier_kind);
            result_index += 1;
        }
    }

    return result;
}

fn parse_modifier_array(array: []const []const u8) !modifier.Set {
    var result = modifier.Set{};

    for (array) |item| {
        if (modifier.Kind.from_string(item)) |kind| {
            result.flags |= kind.to_flag();
        }
    }

    return result;
}

fn parse_shortcut(shortcut: *const ZonShortcut) !Shortcut {
    if (shortcut.sequence) |sequence| {
        const parsed_sequence = try Sequence.init(sequence);
        return Shortcut{ .sequence = parsed_sequence };
    }

    var combination = Combination{};

    if (shortcut.modifiers) |array| {
        combination.modifier_set = try parse_modifier_array(array);
    }

    if (shortcut.key) |string| {
        combination.value = keycode.from_string(string) orelse {
            return Error.InvalidKey;
        };
    } else {
        return Error.InvalidKey;
    }

    return Shortcut{ .combination = combination };
}

fn parse_zon_combination(zon: *const ZonCombination) !Combination {
    var combination = Combination{};

    if (zon.modifiers) |array| {
        combination.modifier_set = try parse_modifier_array(array);
    }

    combination.value = keycode.from_string(zon.key) orelse {
        return Error.InvalidKey;
    };

    return combination;
}

fn shortcut_to_zon(allocator: std.mem.Allocator, shortcut: *const Shortcut) !ZonShortcut {
    switch (shortcut.*) {
        .combination => |combination| {
            std.debug.assert(combination.is_valid());

            return ZonShortcut{
                .modifiers = try modifier_set_to_string(allocator, &combination.modifier_set),
                .key = try keycode_to_string(allocator, combination.value),
            };
        },
        .sequence => |sequence| {
            std.debug.assert(sequence.is_valid());

            const slice = sequence.to_slice();
            const copy = try allocator.alloc(u8, slice.len);

            @memcpy(copy, slice);

            return ZonShortcut{
                .sequence = copy,
            };
        },
    }
}
