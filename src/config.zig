const std = @import("std");

const toolkit = @import("toolkit");

pub const ConfigError = error{
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

pub const ShortcutType = enum {
    combination,
    sequence,
};

pub const KeyCombination = struct {
    key: u32 = 0,
    modifier: toolkit.input.ModifierSet = .{},

    pub fn matches(self: KeyCombination, code: u32, current: toolkit.input.ModifierSet) bool {
        std.debug.assert(self.key > 0);
        std.debug.assert(code > 0);

        if (self.key != code) {
            return false;
        }

        if (!self.modifier.eql(current)) {
            return false;
        }

        return true;
    }
};

pub const KeySequence = struct {
    pub const max: u32 = 32;

    data: [max]u8 = [_]u8{0} ** max,
    len: u32 = 0,

    pub fn init(source: []const u8) ConfigError!KeySequence {
        const length: u32 = @intCast(source.len);

        if (length == 0) {
            return ConfigError.InvalidKey;
        }

        if (length > max) {
            return ConfigError.SequenceTooLong;
        }

        std.debug.assert(length > 0);
        std.debug.assert(length <= max);

        var result = KeySequence{};
        var index: u32 = 0;

        while (index < length) : (index += 1) {
            std.debug.assert(index < max);
            std.debug.assert(index < length);

            result.data[index] = toVirtualKey(source[index]);
        }

        std.debug.assert(index == length);

        result.len = length;

        std.debug.assert(result.len > 0);
        std.debug.assert(result.len <= max);
        std.debug.assert(result.len == length);

        return result;
    }

    fn toVirtualKey(character: u8) u8 {
        std.debug.assert(character > 0);

        if (character >= 'a' and character <= 'z') {
            return character - 32;
        }

        if (character >= 'A' and character <= 'Z') {
            return character;
        }

        if (character >= '0' and character <= '9') {
            return character;
        }

        return character;
    }

    pub fn toSlice(self: *const KeySequence) []const u8 {
        std.debug.assert(self.len <= max);

        return self.data[0..self.len];
    }
};

pub const Shortcut = union(ShortcutType) {
    combination: KeyCombination,
    sequence: KeySequence,
};

pub const Remap = struct {
    from: KeyCombination,
    to: KeyCombination,
};

const ZonShortcut = struct {
    key: ?[]const u8 = null,
    modifiers: ?[]const []const u8 = null,
    sequence: ?[]const u8 = null,
};

const ZonKeyCombination = struct {
    key: []const u8,
    modifiers: ?[]const []const u8 = null,
};

const ZonRemap = struct {
    from: ZonKeyCombination,
    to: ZonKeyCombination,
};

const ZonConfig = struct {
    disabled: ?[]const ZonKeyCombination = null,
    is_keyboard_locked: bool = true,
    is_mouse_locked: bool = false,
    lock: ?ZonShortcut = null,
    remap: ?[]const ZonRemap = null,
    show_notification: bool = true,
    unlock: ?ZonShortcut = null,
};

pub const Config = struct {
    pub const arena_size: u32 = 1024 * 128;
    pub const content_max: u32 = 1024 * 64;
    pub const disabled_max: u32 = 64;
    pub const modifier_count: u32 = 4;
    pub const modifier_max: u32 = 16;
    pub const path_max: u32 = 512;
    pub const remap_max: u32 = 64;
    pub const sequence_buffer_max: u32 = 8;

    allocator: std.mem.Allocator,
    arena: std.heap.FixedBufferAllocator = undefined,
    arena_buffer: [arena_size]u8 = undefined,
    config_path: [path_max]u8 = [_]u8{0} ** path_max,
    config_path_len: u32 = 0,
    disabled_count: u32 = 0,
    disabled_entry: [disabled_max]KeyCombination = [_]KeyCombination{.{}} ** disabled_max,
    is_keyboard_locked: bool = true,
    is_loaded_from_file: bool = false,
    is_mouse_locked: bool = false,
    lock_sequence_buffer: [sequence_buffer_max]u8 = [_]u8{0} ** sequence_buffer_max,
    lock_sequence_len: u32 = 0,
    lock_shortcut: Shortcut,
    remap_count: u32 = 0,
    remap_entry: [remap_max]Remap = [_]Remap{.{ .from = .{}, .to = .{} }} ** remap_max,
    show_notification: bool = true,
    unlock_sequence_buffer: [sequence_buffer_max]u8 = [_]u8{0} ** sequence_buffer_max,
    unlock_sequence_len: u32 = 0,
    unlock_shortcut: Shortcut,

    pub fn init(allocator: std.mem.Allocator) Config {
        var cfg = Config{
            .lock_shortcut = .{
                .combination = .{
                    .modifier = .{ .ctrl = true, .alt = true },
                    .key = 'L',
                },
            },
            .unlock_shortcut = .{
                .sequence = KeySequence.init("UNLOCK") catch @panic("Failed to initialize default unlock sequence"),
            },
            .allocator = allocator,
        };

        cfg.arena = std.heap.FixedBufferAllocator.init(&cfg.arena_buffer);

        return cfg;
    }

    pub fn deinit(self: *Config) void {
        _ = self;
    }

    fn buildCombinationSequence(self: *Config, combination: KeyCombination, buffer: *[sequence_buffer_max]u8, is_lock: bool) void {
        std.debug.assert(combination.key > 0);

        var index: u32 = 0;
        const modifier = combination.modifier.toArray();
        var mod_index: u32 = 0;

        while (mod_index < modifier_count) : (mod_index += 1) {
            std.debug.assert(mod_index < modifier_count);

            if (modifier[mod_index]) |mod| {
                std.debug.assert(index < sequence_buffer_max);

                buffer[index] = @truncate(mod.toVirtualKey());
                index += 1;
            }
        }

        std.debug.assert(mod_index == modifier_count);
        std.debug.assert(index < sequence_buffer_max);

        buffer[index] = @truncate(combination.key);
        index += 1;

        if (is_lock) {
            self.lock_sequence_len = index;
        } else {
            self.unlock_sequence_len = index;
        }

        std.debug.assert(index > 0);
        std.debug.assert(index <= sequence_buffer_max);
    }

    fn buildZonDisabled(self: *Config, alloc: std.mem.Allocator) !?[]const ZonKeyCombination {
        if (self.disabled_count == 0) {
            return null;
        }

        std.debug.assert(self.disabled_count > 0);
        std.debug.assert(self.disabled_count <= disabled_max);

        const slice = try alloc.alloc(ZonKeyCombination, self.disabled_count);

        std.debug.assert(slice.len == self.disabled_count);

        var index: u32 = 0;

        while (index < self.disabled_count) : (index += 1) {
            std.debug.assert(index < disabled_max);
            std.debug.assert(index < self.disabled_count);
            std.debug.assert(self.disabled_entry[index].key > 0);

            slice[index] = try keyCombinationToZon(alloc, self.disabled_entry[index]);
        }

        std.debug.assert(index == self.disabled_count);

        return slice;
    }

    fn buildZonRemap(self: *Config, alloc: std.mem.Allocator) !?[]const ZonRemap {
        if (self.remap_count == 0) {
            return null;
        }

        std.debug.assert(self.remap_count > 0);
        std.debug.assert(self.remap_count <= remap_max);

        const slice = try alloc.alloc(ZonRemap, self.remap_count);

        std.debug.assert(slice.len == self.remap_count);

        var index: u32 = 0;

        while (index < self.remap_count) : (index += 1) {
            std.debug.assert(index < remap_max);
            std.debug.assert(index < self.remap_count);

            const entry = self.remap_entry[index];

            std.debug.assert(entry.from.key > 0);
            std.debug.assert(entry.to.key > 0);

            slice[index] = .{
                .from = try keyCombinationToZon(alloc, entry.from),
                .to = try keyCombinationToZon(alloc, entry.to),
            };
        }

        std.debug.assert(index == self.remap_count);

        return slice;
    }

    fn ensureDirectoryExists(path: []const u8) !void {
        std.debug.assert(path.len > 0);

        const directory = std.fs.path.dirname(path) orelse return error.InvalidPath;

        std.debug.assert(directory.len > 0);
        std.debug.assert(directory.len < path.len);

        std.fs.makeDirAbsolute(directory) catch |err| {
            if (err != error.PathAlreadyExists) {
                return err;
            }
        };
    }

    fn loadConfigPath(self: *Config) !void {
        const directory = try std.fs.getAppDataDir(self.allocator, "locker");
        defer self.allocator.free(directory);

        std.debug.assert(directory.len > 0);

        const path = try std.fs.path.join(self.allocator, &[_][]const u8{ directory, "config.zon" });
        defer self.allocator.free(path);

        const length: u32 = @intCast(path.len);

        if (length > path_max) {
            return ConfigError.InvalidPath;
        }

        std.debug.assert(length > 0);
        std.debug.assert(length <= path_max);

        @memcpy(self.config_path[0..length], path);
        self.config_path_len = length;

        std.debug.assert(self.config_path_len > 0);
        std.debug.assert(self.config_path_len <= path_max);
    }

    fn loadFromFile(self: *Config) !void {
        std.debug.assert(self.config_path_len > 0);
        std.debug.assert(self.config_path_len <= path_max);

        const path = self.config_path[0..self.config_path_len];

        const file = std.fs.openFileAbsolute(path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                self.is_loaded_from_file = true;
                try self.save();
                return;
            }

            return err;
        };

        defer file.close();

        const alloc = self.arena.allocator();

        const content = alloc.allocSentinel(u8, content_max, 0) catch {
            return ConfigError.BufferTooSmall;
        };

        const count = file.readAll(content) catch {
            return ConfigError.ParseError;
        };

        if (count == 0) {
            return ConfigError.ParseError;
        }

        const slice: [:0]const u8 = content[0..count :0];

        try self.parse(slice);
        self.is_loaded_from_file = true;
    }

    fn parseDisabledArray(self: *Config, array: []const ZonKeyCombination) !void {
        const length: u32 = @intCast(array.len);

        if (length > disabled_max) {
            return ConfigError.TooManyDisabled;
        }

        std.debug.assert(length <= disabled_max);

        self.disabled_count = 0;
        var index: u32 = 0;

        while (index < length) : (index += 1) {
            std.debug.assert(index < disabled_max);
            std.debug.assert(index < length);

            const combination = try parseZonKeyCombination(array[index]);

            std.debug.assert(combination.key > 0);

            self.disabled_entry[index] = combination;
            self.disabled_count += 1;
        }

        std.debug.assert(index == length);
        std.debug.assert(self.disabled_count == length);
    }

    fn parseRemapArray(self: *Config, array: []const ZonRemap) !void {
        const length: u32 = @intCast(array.len);

        if (length > remap_max) {
            return ConfigError.TooManyRemap;
        }

        std.debug.assert(length <= remap_max);

        self.remap_count = 0;
        var index: u32 = 0;

        while (index < length) : (index += 1) {
            std.debug.assert(index < remap_max);
            std.debug.assert(index < length);

            const from = try parseZonKeyCombination(array[index].from);
            const to = try parseZonKeyCombination(array[index].to);

            std.debug.assert(from.key > 0);
            std.debug.assert(to.key > 0);

            self.remap_entry[index] = .{ .from = from, .to = to };
            self.remap_count += 1;
        }

        std.debug.assert(index == length);
        std.debug.assert(self.remap_count == length);
    }

    fn toZonConfig(self: *Config) !ZonConfig {
        const alloc = self.arena.allocator();

        return .{
            .is_keyboard_locked = self.is_keyboard_locked,
            .is_mouse_locked = self.is_mouse_locked,
            .show_notification = self.show_notification,
            .lock = try shortcutToZon(alloc, self.lock_shortcut),
            .unlock = try shortcutToZon(alloc, self.unlock_shortcut),
            .remap = try self.buildZonRemap(alloc),
            .disabled = try self.buildZonDisabled(alloc),
        };
    }

    fn writeConfigFile(self: *Config, path: []const u8) !void {
        std.debug.assert(path.len > 0);

        const file = try std.fs.createFileAbsolute(path, .{});
        defer file.close();

        var allocating: std.Io.Writer.Allocating = .init(self.allocator);
        defer allocating.deinit();

        const zon = try self.toZonConfig();
        try std.zon.stringify.serialize(zon, .{}, &allocating.writer);

        var buffer: [4096]u8 = undefined;
        var writer: std.fs.File.Writer = .init(file, &buffer);

        try writer.interface.writeAll(allocating.writer.buffered());
        try writer.interface.flush();
    }

    pub fn findRemap(self: *const Config, code: u32, modifier: toolkit.input.ModifierSet) ?KeyCombination {
        std.debug.assert(self.remap_count <= remap_max);
        std.debug.assert(code > 0);

        const slice = self.getRemapSlice();

        for (slice) |entry| {
            if (entry.from.matches(code, modifier)) {
                return entry.to;
            }
        }

        return null;
    }

    pub fn findRemapEntry(self: *const Config, code: u32, modifier: toolkit.input.ModifierSet) ?Remap {
        std.debug.assert(self.remap_count <= remap_max);
        std.debug.assert(code > 0);

        const slice = self.getRemapSlice();

        for (slice) |entry| {
            if (entry.from.matches(code, modifier)) {
                return entry;
            }
        }

        return null;
    }

    pub fn getConfigPath(self: *Config) ?[]const u8 {
        if (self.config_path_len == 0) {
            return null;
        }

        std.debug.assert(self.config_path_len > 0);
        std.debug.assert(self.config_path_len <= path_max);

        return self.config_path[0..self.config_path_len];
    }

    pub fn getDisabledSlice(self: *const Config) []const KeyCombination {
        std.debug.assert(self.disabled_count <= disabled_max);

        return self.disabled_entry[0..self.disabled_count];
    }

    pub fn getLockSequence(self: *Config) ?[]const u8 {
        switch (self.lock_shortcut) {
            .combination => |combination| {
                std.debug.assert(combination.key > 0);

                self.buildCombinationSequence(combination, &self.lock_sequence_buffer, true);

                if (self.lock_sequence_len == 0) {
                    return null;
                }

                return self.lock_sequence_buffer[0..self.lock_sequence_len];
            },
            .sequence => |*seq| {
                std.debug.assert(seq.len > 0);

                return seq.toSlice();
            },
        }
    }

    pub fn getRemapSlice(self: *const Config) []const Remap {
        std.debug.assert(self.remap_count <= remap_max);

        return self.remap_entry[0..self.remap_count];
    }

    pub fn getUnlockSequence(self: *Config) ?[]const u8 {
        switch (self.unlock_shortcut) {
            .combination => |combination| {
                std.debug.assert(combination.key > 0);

                self.buildCombinationSequence(combination, &self.unlock_sequence_buffer, false);

                if (self.unlock_sequence_len == 0) {
                    return null;
                }

                return self.unlock_sequence_buffer[0..self.unlock_sequence_len];
            },
            .sequence => |*seq| {
                std.debug.assert(seq.len > 0);

                return seq.toSlice();
            },
        }
    }

    pub fn isDisabled(self: *const Config, code: u32, modifier: toolkit.input.ModifierSet) bool {
        std.debug.assert(self.disabled_count <= disabled_max);
        std.debug.assert(code > 0);

        const slice = self.getDisabledSlice();

        for (slice) |entry| {
            if (entry.matches(code, modifier)) {
                return true;
            }
        }

        return false;
    }

    pub fn load(allocator: std.mem.Allocator) !Config {
        var cfg = Config.init(allocator);
        errdefer cfg.deinit();

        try cfg.loadConfigPath();

        std.debug.assert(cfg.config_path_len > 0);
        std.debug.assert(cfg.config_path_len <= path_max);

        try cfg.loadFromFile();

        return cfg;
    }

    pub fn parse(self: *Config, content: [:0]const u8) !void {
        std.debug.assert(content.len > 0);
        std.debug.assert(content.len <= content_max);

        const alloc = self.arena.allocator();

        const parsed = std.zon.parse.fromSlice(ZonConfig, alloc, content, null, .{}) catch {
            return ConfigError.ParseError;
        };

        self.is_keyboard_locked = parsed.is_keyboard_locked;
        self.is_mouse_locked = parsed.is_mouse_locked;
        self.show_notification = parsed.show_notification;

        if (parsed.lock) |lock| {
            self.lock_shortcut = try parseShortcut(lock);
        }

        if (parsed.unlock) |unlock| {
            self.unlock_shortcut = try parseShortcut(unlock);
        }

        if (parsed.remap) |array| {
            try self.parseRemapArray(array);
        }

        if (parsed.disabled) |array| {
            try self.parseDisabledArray(array);
        }
    }

    pub fn reset(self: *Config) void {
        self.arena.reset();
        self.remap_count = 0;
        self.disabled_count = 0;
        self.lock_shortcut = .{
            .combination = .{
                .modifier = .{ .ctrl = true, .alt = true },
                .key = 'L',
            },
        };
        self.unlock_shortcut = .{
            .sequence = KeySequence.init("UNLOCK") catch @panic("Failed to initialize default unlock sequence"),
        };
        self.is_keyboard_locked = true;
        self.is_mouse_locked = false;
        self.show_notification = true;
    }

    pub fn save(self: *Config) !void {
        if (!self.is_loaded_from_file) {
            return;
        }

        std.debug.assert(self.is_loaded_from_file);
        std.debug.assert(self.config_path_len > 0);
        std.debug.assert(self.config_path_len <= path_max);

        const path = self.config_path[0..self.config_path_len];

        try ensureDirectoryExists(path);
        try self.writeConfigFile(path);
    }
};

fn keyCombinationToZon(alloc: std.mem.Allocator, combination: KeyCombination) !ZonKeyCombination {
    std.debug.assert(combination.key > 0);

    const str = try keyToString(alloc, combination.key) orelse {
        return ConfigError.InvalidKey;
    };

    std.debug.assert(str.len > 0);

    return .{
        .modifiers = try modifierSetToString(alloc, combination.modifier),
        .key = str,
    };
}

fn keyToString(alloc: std.mem.Allocator, key: u32) !?[]const u8 {
    std.debug.assert(key > 0);

    if (key >= 'A' and key <= 'Z') {
        const buffer = try alloc.alloc(u8, 1);
        buffer[0] = @truncate(key);
        return buffer;
    }

    if (key >= '0' and key <= '9') {
        const buffer = try alloc.alloc(u8, 1);
        buffer[0] = @truncate(key);
        return buffer;
    }

    return toolkit.input.VirtualKey.toString(key);
}

fn modifierSetToString(alloc: std.mem.Allocator, modifier: toolkit.input.ModifierSet) !?[]const []const u8 {
    const array = modifier.toArray();

    var count: u32 = 0;

    for (array) |maybe_mod| {
        if (maybe_mod != null) {
            count += 1;
        }
    }

    if (count == 0) {
        return null;
    }

    const result = try alloc.alloc([]const u8, count);
    var index: u32 = 0;

    for (array) |maybe_mod| {
        if (maybe_mod) |mod| {
            result[index] = @tagName(mod);
            index += 1;
        }
    }

    return result;
}

fn parseModifierArray(array: []const []const u8) !toolkit.input.ModifierSet {
    var result = toolkit.input.ModifierSet{};

    for (array) |string| {
        if (toolkit.input.Modifier.fromString(string)) |modifier| {
            switch (modifier) {
                .ctrl => result.ctrl = true,
                .alt => result.alt = true,
                .shift => result.shift = true,
                .win => result.win = true,
            }
        }
    }

    return result;
}

fn parseShortcut(shortcut: ZonShortcut) !Shortcut {
    if (shortcut.sequence) |sequence| {
        std.debug.assert(sequence.len > 0);

        const result = try KeySequence.init(sequence);

        std.debug.assert(result.len > 0);

        return .{ .sequence = result };
    }

    var combination = KeyCombination{};

    if (shortcut.modifiers) |array| {
        combination.modifier = try parseModifierArray(array);
    }

    if (shortcut.key) |string| {
        std.debug.assert(string.len > 0);

        combination.key = toolkit.input.VirtualKey.fromString(string) orelse {
            return ConfigError.InvalidKey;
        };
    } else {
        return ConfigError.InvalidKey;
    }

    std.debug.assert(combination.key > 0);

    return .{ .combination = combination };
}

fn parseZonKeyCombination(zon: ZonKeyCombination) !KeyCombination {
    var combination = KeyCombination{};

    if (zon.modifiers) |array| {
        combination.modifier = try parseModifierArray(array);
    }

    std.debug.assert(zon.key.len > 0);

    combination.key = toolkit.input.VirtualKey.fromString(zon.key) orelse {
        return ConfigError.InvalidKey;
    };

    std.debug.assert(combination.key > 0);

    return combination;
}

fn shortcutToZon(alloc: std.mem.Allocator, shortcut: Shortcut) !ZonShortcut {
    return switch (shortcut) {
        .combination => |c| .{
            .modifiers = try modifierSetToString(alloc, c.modifier),
            .key = try keyToString(alloc, c.key),
        },
        .sequence => |s| .{
            .sequence = s.toSlice(),
        },
    };
}

const testing = std.testing;

test "KeySequence.init valid" {
    const seq = try KeySequence.init("UNLOCK");

    try testing.expectEqual(@as(u32, 6), seq.len);
    try testing.expectEqualStrings("UNLOCK", seq.toSlice());
}

test "KeySequence.init lowercase converts" {
    const seq = try KeySequence.init("unlock");

    try testing.expectEqualStrings("UNLOCK", seq.toSlice());
}

test "KeySequence.init empty fails" {
    try testing.expectError(ConfigError.InvalidKey, KeySequence.init(""));
}

test "KeyCombination.matches" {
    const combo = KeyCombination{
        .modifier = .{ .ctrl = true, .alt = true },
        .key = 'L',
    };

    try testing.expect(combo.matches('L', .{ .ctrl = true, .alt = true }));
    try testing.expect(!combo.matches('K', .{ .ctrl = true, .alt = true }));
    try testing.expect(!combo.matches('L', .{ .ctrl = true }));
}

test "Config.init defaults" {
    var cfg = Config.init(testing.allocator);
    defer cfg.deinit();

    try testing.expect(cfg.is_keyboard_locked);
    try testing.expect(!cfg.is_mouse_locked);
    try testing.expect(cfg.show_notification);
}
