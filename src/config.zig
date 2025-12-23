const std = @import("std");

const keycode = @import("input/keycode.zig");

pub const ConfigError = error{
    InvalidShortcut,
    InvalidKey,
    InvalidModifier,
    ParseError,
    InvalidPath,
    SequenceTooLong,
    TooManyRemaps,
    TooManyDisabled,
    BufferTooSmall,
};

pub const ShortcutType = enum {
    combination,
    sequence,
};

pub const KeyCombination = struct {
    modifier: keycode.ModifierSet = .{},
    key: u32 = 0,

    pub fn matches(self: KeyCombination, virtual_key_code: u32, current_modifier: keycode.ModifierSet) bool {
        std.debug.assert(self.key > 0);
        std.debug.assert(virtual_key_code > 0);

        if (self.key != virtual_key_code) {
            return false;
        }

        if (!self.modifier.eql(current_modifier)) {
            return false;
        }

        return true;
    }
};

pub const KeySequence = struct {
    pub const sequence_max: u32 = 32;

    data: [sequence_max]u8 = [_]u8{0} ** sequence_max,
    len: u32 = 0,

    pub fn init(source: []const u8) ConfigError!KeySequence {
        const source_len: u32 = @intCast(source.len);

        if (source_len == 0) {
            return ConfigError.InvalidKey;
        }

        if (source_len > sequence_max) {
            return ConfigError.SequenceTooLong;
        }

        std.debug.assert(source_len > 0);
        std.debug.assert(source_len <= sequence_max);

        var result = KeySequence{};
        var index: u32 = 0;

        while (index < source_len) : (index += 1) {
            std.debug.assert(index < sequence_max);
            std.debug.assert(index < source_len);

            result.data[index] = toVirtualKey(source[index]);
        }

        std.debug.assert(index == source_len);

        result.len = source_len;

        std.debug.assert(result.len > 0);
        std.debug.assert(result.len <= sequence_max);
        std.debug.assert(result.len == source_len);

        return result;
    }

    fn toVirtualKey(character: u8) u8 {
        std.debug.assert(character > 0);

        if (character >= 'a') {
            if (character <= 'z') {
                return character - 32;
            }
        }

        if (character >= 'A') {
            if (character <= 'Z') {
                return character;
            }
        }

        if (character >= '0') {
            if (character <= '9') {
                return character;
            }
        }

        return character;
    }

    pub fn toSlice(self: *const KeySequence) []const u8 {
        std.debug.assert(self.len <= sequence_max);

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
    modifiers: ?[]const []const u8 = null,
    key: ?[]const u8 = null,
    sequence: ?[]const u8 = null,
};

const ZonKeyCombination = struct {
    modifiers: ?[]const []const u8 = null,
    key: []const u8,
};

const ZonRemap = struct {
    from: ZonKeyCombination,
    to: ZonKeyCombination,
};

const ZonConfig = struct {
    is_keyboard_locked: bool = true,
    is_mouse_locked: bool = false,
    show_notification: bool = true,
    lock: ?ZonShortcut = null,
    unlock: ?ZonShortcut = null,
    remap: ?[]const ZonRemap = null,
    disabled: ?[]const ZonKeyCombination = null,
};

pub const Config = struct {
    pub const content_max: u32 = 1024 * 64;
    pub const remap_max: u32 = 64;
    pub const disabled_max: u32 = 64;
    pub const path_max: u32 = 512;
    pub const sequence_buffer_max: u32 = 8;
    pub const modifier_max: u32 = 16;
    pub const modifier_count: u32 = 4;
    pub const arena_size: u32 = 1024 * 128;

    lock_shortcut: Shortcut,
    unlock_shortcut: Shortcut,

    remap_entries: [remap_max]Remap = [_]Remap{.{ .from = .{}, .to = .{} }} ** remap_max,
    remap_count: u32 = 0,

    disabled_entries: [disabled_max]KeyCombination = [_]KeyCombination{.{}} ** disabled_max,
    disabled_count: u32 = 0,

    is_keyboard_locked: bool = true,
    is_mouse_locked: bool = false,
    show_notification: bool = true,
    is_loaded_from_file: bool = false,

    config_path: [path_max]u8 = [_]u8{0} ** path_max,
    config_path_len: u32 = 0,

    lock_sequence_buffer: [sequence_buffer_max]u8 = [_]u8{0} ** sequence_buffer_max,
    lock_sequence_len: u32 = 0,

    unlock_sequence_buffer: [sequence_buffer_max]u8 = [_]u8{0} ** sequence_buffer_max,
    unlock_sequence_len: u32 = 0,

    arena_buffer: [arena_size]u8 = undefined,
    arena: std.heap.FixedBufferAllocator = undefined,

    allocator: std.mem.Allocator,

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

    fn buildZonDisabled(self: *Config, arena_alloc: std.mem.Allocator) !?[]const ZonKeyCombination {
        if (self.disabled_count == 0) {
            return null;
        }

        std.debug.assert(self.disabled_count > 0);
        std.debug.assert(self.disabled_count <= disabled_max);

        const disabled_slice = try arena_alloc.alloc(ZonKeyCombination, self.disabled_count);

        std.debug.assert(disabled_slice.len == self.disabled_count);

        var index: u32 = 0;

        while (index < self.disabled_count) : (index += 1) {
            std.debug.assert(index < disabled_max);
            std.debug.assert(index < self.disabled_count);
            std.debug.assert(self.disabled_entries[index].key > 0);

            disabled_slice[index] = try keyCombinationToZon(arena_alloc, self.disabled_entries[index]);
        }

        std.debug.assert(index == self.disabled_count);

        return disabled_slice;
    }

    fn buildZonRemap(self: *Config, arena_alloc: std.mem.Allocator) !?[]const ZonRemap {
        if (self.remap_count == 0) {
            return null;
        }

        std.debug.assert(self.remap_count > 0);
        std.debug.assert(self.remap_count <= remap_max);

        const remap_slice = try arena_alloc.alloc(ZonRemap, self.remap_count);

        std.debug.assert(remap_slice.len == self.remap_count);

        var index: u32 = 0;

        while (index < self.remap_count) : (index += 1) {
            std.debug.assert(index < remap_max);
            std.debug.assert(index < self.remap_count);

            const entry = self.remap_entries[index];

            std.debug.assert(entry.from.key > 0);
            std.debug.assert(entry.to.key > 0);

            remap_slice[index] = .{
                .from = try keyCombinationToZon(arena_alloc, entry.from),
                .to = try keyCombinationToZon(arena_alloc, entry.to),
            };
        }

        std.debug.assert(index == self.remap_count);

        return remap_slice;
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

        const path_len: u32 = @intCast(path.len);

        if (path_len > path_max) {
            return ConfigError.InvalidPath;
        }

        std.debug.assert(path_len > 0);
        std.debug.assert(path_len <= path_max);

        @memcpy(self.config_path[0..path_len], path);
        self.config_path_len = path_len;

        std.debug.assert(self.config_path_len > 0);
        std.debug.assert(self.config_path_len <= path_max);
        std.debug.assert(self.config_path_len == path_len);
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

        const arena_alloc = self.arena.allocator();
        const content = arena_alloc.allocSentinel(u8, content_max, 0) catch {
            return ConfigError.BufferTooSmall;
        };

        const bytes_read = file.readAll(content) catch {
            return ConfigError.ParseError;
        };

        if (bytes_read == 0) {
            return ConfigError.ParseError;
        }

        const content_slice: [:0]const u8 = content[0..bytes_read :0];

        try self.parse(content_slice);
        self.is_loaded_from_file = true;
    }

    pub fn parse(self: *Config, content: [:0]const u8) !void {
        std.debug.assert(content.len > 0);
        std.debug.assert(content.len <= content_max);

        const arena_alloc = self.arena.allocator();

        const parsed = std.zon.parse.fromSlice(ZonConfig, arena_alloc, content, null, .{}) catch {
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

        if (parsed.remap) |remap_array| {
            try self.parseRemapArray(remap_array);
        }

        if (parsed.disabled) |disabled_array| {
            try self.parseDisabledArray(disabled_array);
        }
    }

    fn parseDisabledArray(self: *Config, disabled_array: []const ZonKeyCombination) !void {
        const disabled_len: u32 = @intCast(disabled_array.len);

        if (disabled_len > disabled_max) {
            return ConfigError.TooManyDisabled;
        }

        std.debug.assert(disabled_len <= disabled_max);

        self.disabled_count = 0;
        var index: u32 = 0;

        while (index < disabled_len) : (index += 1) {
            std.debug.assert(index < disabled_max);
            std.debug.assert(index < disabled_len);
            std.debug.assert(index == self.disabled_count);

            const combination = try parseZonKeyCombination(disabled_array[index]);

            std.debug.assert(combination.key > 0);

            self.disabled_entries[index] = combination;
            self.disabled_count += 1;
        }

        std.debug.assert(index == disabled_len);
        std.debug.assert(self.disabled_count == disabled_len);
        std.debug.assert(self.disabled_count <= disabled_max);
    }

    fn parseRemapArray(self: *Config, remap_array: []const ZonRemap) !void {
        const remap_len: u32 = @intCast(remap_array.len);

        if (remap_len > remap_max) {
            return ConfigError.TooManyRemaps;
        }

        std.debug.assert(remap_len <= remap_max);

        self.remap_count = 0;
        var index: u32 = 0;

        while (index < remap_len) : (index += 1) {
            std.debug.assert(index < remap_max);
            std.debug.assert(index < remap_len);
            std.debug.assert(index == self.remap_count);

            const from = try parseZonKeyCombination(remap_array[index].from);
            const to = try parseZonKeyCombination(remap_array[index].to);

            std.debug.assert(from.key > 0);
            std.debug.assert(to.key > 0);

            self.remap_entries[index] = .{ .from = from, .to = to };
            self.remap_count += 1;
        }

        std.debug.assert(index == remap_len);
        std.debug.assert(self.remap_count == remap_len);
        std.debug.assert(self.remap_count <= remap_max);
    }

    fn toZonConfig(self: *Config) !ZonConfig {
        const arena_alloc = self.arena.allocator();

        const zon_remap = try self.buildZonRemap(arena_alloc);
        const zon_disabled = try self.buildZonDisabled(arena_alloc);

        return .{
            .is_keyboard_locked = self.is_keyboard_locked,
            .is_mouse_locked = self.is_mouse_locked,
            .show_notification = self.show_notification,
            .lock = try shortcutToZon(arena_alloc, self.lock_shortcut),
            .unlock = try shortcutToZon(arena_alloc, self.unlock_shortcut),
            .remap = zon_remap,
            .disabled = zon_disabled,
        };
    }

    fn writeConfigFile(self: *Config, path: []const u8) !void {
        std.debug.assert(path.len > 0);

        const file = try std.fs.createFileAbsolute(path, .{});

        defer file.close();

        var allocating: std.Io.Writer.Allocating = .init(self.allocator);

        defer allocating.deinit();

        const zon_config = try self.toZonConfig();
        try std.zon.stringify.serialize(zon_config, .{}, &allocating.writer);

        var buffer: [4096]u8 = undefined;
        var file_writer: std.fs.File.Writer = .init(file, &buffer);

        try file_writer.interface.writeAll(allocating.writer.buffered());
        try file_writer.interface.flush();
    }

    pub fn findRemap(self: *const Config, virtual_key_code: u32, modifier: keycode.ModifierSet) ?KeyCombination {
        std.debug.assert(self.remap_count <= remap_max);
        std.debug.assert(virtual_key_code > 0);

        const entries = self.getRemapSlice();
        const entries_len: u32 = @intCast(entries.len);

        std.debug.assert(entries_len == self.remap_count);
        std.debug.assert(entries_len <= remap_max);

        var index: u32 = 0;

        while (index < entries_len) : (index += 1) {
            std.debug.assert(index < remap_max);
            std.debug.assert(index < entries_len);

            if (entries[index].from.matches(virtual_key_code, modifier)) {
                return entries[index].to;
            }
        }

        std.debug.assert(index == entries_len);

        return null;
    }

    pub fn findRemapEntry(self: *const Config, virtual_key_code: u32, modifier: keycode.ModifierSet) ?Remap {
        std.debug.assert(self.remap_count <= remap_max);
        std.debug.assert(virtual_key_code > 0);

        const entries = self.getRemapSlice();
        const entries_len: u32 = @intCast(entries.len);

        std.debug.assert(entries_len == self.remap_count);
        std.debug.assert(entries_len <= remap_max);

        var index: u32 = 0;

        while (index < entries_len) : (index += 1) {
            std.debug.assert(index < remap_max);
            std.debug.assert(index < entries_len);

            if (entries[index].from.matches(virtual_key_code, modifier)) {
                return entries[index];
            }
        }

        std.debug.assert(index == entries_len);

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

        return self.disabled_entries[0..self.disabled_count];
    }

    pub fn getLockSequence(self: *Config) ?[]const u8 {
        std.debug.assert(self.lock_shortcut == .combination or self.lock_shortcut == .sequence);

        switch (self.lock_shortcut) {
            .combination => |combination| {
                std.debug.assert(combination.key > 0);

                self.buildCombinationSequence(combination, &self.lock_sequence_buffer, true);

                if (self.lock_sequence_len == 0) {
                    return null;
                }

                std.debug.assert(self.lock_sequence_len > 0);
                std.debug.assert(self.lock_sequence_len <= sequence_buffer_max);

                return self.lock_sequence_buffer[0..self.lock_sequence_len];
            },
            .sequence => |*sequence| {
                std.debug.assert(sequence.len > 0);
                std.debug.assert(sequence.len <= KeySequence.sequence_max);

                return sequence.toSlice();
            },
        }
    }

    pub fn getRemapSlice(self: *const Config) []const Remap {
        std.debug.assert(self.remap_count <= remap_max);

        return self.remap_entries[0..self.remap_count];
    }

    pub fn getUnlockSequence(self: *Config) ?[]const u8 {
        std.debug.assert(self.unlock_shortcut == .combination or self.unlock_shortcut == .sequence);

        switch (self.unlock_shortcut) {
            .combination => |combination| {
                std.debug.assert(combination.key > 0);

                self.buildCombinationSequence(combination, &self.unlock_sequence_buffer, false);

                if (self.unlock_sequence_len == 0) {
                    return null;
                }

                std.debug.assert(self.unlock_sequence_len > 0);
                std.debug.assert(self.unlock_sequence_len <= sequence_buffer_max);

                return self.unlock_sequence_buffer[0..self.unlock_sequence_len];
            },
            .sequence => |*sequence| {
                std.debug.assert(sequence.len > 0);
                std.debug.assert(sequence.len <= KeySequence.sequence_max);

                return sequence.toSlice();
            },
        }
    }

    pub fn isDisabled(self: *const Config, virtual_key_code: u32, modifier: keycode.ModifierSet) bool {
        std.debug.assert(self.disabled_count <= disabled_max);
        std.debug.assert(virtual_key_code > 0);

        const entries = self.getDisabledSlice();
        const entries_len: u32 = @intCast(entries.len);

        std.debug.assert(entries_len == self.disabled_count);
        std.debug.assert(entries_len <= disabled_max);

        var index: u32 = 0;

        while (index < entries_len) : (index += 1) {
            std.debug.assert(index < disabled_max);
            std.debug.assert(index < entries_len);

            if (entries[index].matches(virtual_key_code, modifier)) {
                return true;
            }
        }

        std.debug.assert(index == entries_len);

        return false;
    }

    pub fn load(allocator: std.mem.Allocator) !Config {
        var config = Config.init(allocator);
        errdefer config.deinit();

        try config.loadConfigPath();

        std.debug.assert(config.config_path_len > 0);
        std.debug.assert(config.config_path_len <= path_max);

        try config.loadFromFile();

        return config;
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

fn keyCombinationToZon(arena_alloc: std.mem.Allocator, combination: KeyCombination) !ZonKeyCombination {
    std.debug.assert(combination.key > 0);

    const key_str = try keyToString(arena_alloc, combination.key) orelse {
        return ConfigError.InvalidKey;
    };

    std.debug.assert(key_str.len > 0);

    return .{
        .modifiers = try modifierSetToStrings(arena_alloc, combination.modifier),
        .key = key_str,
    };
}

fn keyToString(arena_alloc: std.mem.Allocator, key: u32) !?[]const u8 {
    std.debug.assert(key > 0);

    if (key >= 'A') {
        if (key <= 'Z') {
            const buffer = try arena_alloc.alloc(u8, 1);

            std.debug.assert(buffer.len == 1);

            buffer[0] = @truncate(key);
            return buffer;
        }
    }

    if (key >= '0') {
        if (key <= '9') {
            const buffer = try arena_alloc.alloc(u8, 1);

            std.debug.assert(buffer.len == 1);

            buffer[0] = @truncate(key);
            return buffer;
        }
    }

    return keycode.VirtualKey.fromCode(key);
}

fn modifierSetToStrings(arena_alloc: std.mem.Allocator, modifier: keycode.ModifierSet) !?[]const []const u8 {
    const modifier_array = modifier.toArray();

    var count: u32 = 0;
    var count_index: u32 = 0;

    while (count_index < Config.modifier_count) : (count_index += 1) {
        std.debug.assert(count_index < Config.modifier_count);

        if (modifier_array[count_index] != null) {
            count += 1;
        }
    }

    std.debug.assert(count_index == Config.modifier_count);

    if (count == 0) {
        return null;
    }

    std.debug.assert(count > 0);
    std.debug.assert(count <= Config.modifier_count);

    const result = try arena_alloc.alloc([]const u8, count);

    std.debug.assert(result.len == count);

    var index: u32 = 0;
    var mod_index: u32 = 0;

    while (mod_index < Config.modifier_count) : (mod_index += 1) {
        std.debug.assert(mod_index < Config.modifier_count);

        if (modifier_array[mod_index]) |mod| {
            std.debug.assert(index < count);

            result[index] = @tagName(mod);
            index += 1;
        }
    }

    std.debug.assert(mod_index == Config.modifier_count);
    std.debug.assert(index == count);

    return result;
}

fn parseModifierArray(modifier_array: []const []const u8) !keycode.ModifierSet {
    var result = keycode.ModifierSet{};
    const iteration_max: u32 = Config.modifier_max;
    const array_len: u32 = @intCast(modifier_array.len);

    std.debug.assert(array_len <= iteration_max);

    var iteration: u32 = 0;

    while (iteration < array_len) : (iteration += 1) {
        std.debug.assert(iteration < iteration_max);
        std.debug.assert(iteration < array_len);

        const modifier_string = modifier_array[iteration];

        std.debug.assert(modifier_string.len > 0);

        if (keycode.Modifier.fromString(modifier_string)) |modifier| {
            switch (modifier) {
                .ctrl => result.ctrl = true,
                .alt => result.alt = true,
                .shift => result.shift = true,
                .win => result.win = true,
            }
        }
    }

    std.debug.assert(iteration == array_len);
    std.debug.assert(iteration <= iteration_max);

    return result;
}

fn parseShortcut(shortcut: ZonShortcut) !Shortcut {
    if (shortcut.sequence) |sequence| {
        std.debug.assert(sequence.len > 0);

        const key_sequence = try KeySequence.init(sequence);

        std.debug.assert(key_sequence.len > 0);
        std.debug.assert(key_sequence.len <= KeySequence.sequence_max);

        return .{ .sequence = key_sequence };
    }

    var combination = KeyCombination{};

    if (shortcut.modifiers) |modifier_array| {
        combination.modifier = try parseModifierArray(modifier_array);
    }

    if (shortcut.key) |key_string| {
        std.debug.assert(key_string.len > 0);

        combination.key = keycode.VirtualKey.fromString(key_string) orelse {
            return ConfigError.InvalidKey;
        };
    } else {
        return ConfigError.InvalidKey;
    }

    std.debug.assert(combination.key > 0);

    return .{ .combination = combination };
}

fn parseZonKeyCombination(zon_combination: ZonKeyCombination) !KeyCombination {
    var combination = KeyCombination{};

    if (zon_combination.modifiers) |modifier_array| {
        combination.modifier = try parseModifierArray(modifier_array);
    }

    std.debug.assert(zon_combination.key.len > 0);

    combination.key = keycode.VirtualKey.fromString(zon_combination.key) orelse {
        return ConfigError.InvalidKey;
    };

    std.debug.assert(combination.key > 0);

    return combination;
}

fn shortcutToZon(arena_alloc: std.mem.Allocator, shortcut: Shortcut) !ZonShortcut {
    return switch (shortcut) {
        .combination => |c| .{
            .modifiers = try modifierSetToStrings(arena_alloc, c.modifier),
            .key = try keyToString(arena_alloc, c.key),
        },
        .sequence => |s| .{
            .sequence = s.toSlice(),
        },
    };
}

const testing = std.testing;

test "KeySequence.init with valid sequence" {
    const sequence = try KeySequence.init("UNLOCK");

    try testing.expectEqual(@as(u32, 6), sequence.len);
    try testing.expectEqual(@as(u8, 'U'), sequence.data[0]);
    try testing.expectEqual(@as(u8, 'N'), sequence.data[1]);
    try testing.expectEqual(@as(u8, 'L'), sequence.data[2]);
    try testing.expectEqual(@as(u8, 'O'), sequence.data[3]);
    try testing.expectEqual(@as(u8, 'C'), sequence.data[4]);
    try testing.expectEqual(@as(u8, 'K'), sequence.data[5]);
}

test "KeySequence.init with lowercase converts to uppercase" {
    const sequence = try KeySequence.init("unlock");

    try testing.expectEqual(@as(u32, 6), sequence.len);
    try testing.expectEqual(@as(u8, 'U'), sequence.data[0]);
    try testing.expectEqual(@as(u8, 'N'), sequence.data[1]);
    try testing.expectEqual(@as(u8, 'L'), sequence.data[2]);
    try testing.expectEqual(@as(u8, 'O'), sequence.data[3]);
    try testing.expectEqual(@as(u8, 'C'), sequence.data[4]);
    try testing.expectEqual(@as(u8, 'K'), sequence.data[5]);
}

test "KeySequence.init with mixed case" {
    const sequence = try KeySequence.init("UnLoCk");

    try testing.expectEqual(@as(u32, 6), sequence.len);
    try testing.expectEqual(@as(u8, 'U'), sequence.data[0]);
    try testing.expectEqual(@as(u8, 'N'), sequence.data[1]);
    try testing.expectEqual(@as(u8, 'L'), sequence.data[2]);
    try testing.expectEqual(@as(u8, 'O'), sequence.data[3]);
    try testing.expectEqual(@as(u8, 'C'), sequence.data[4]);
    try testing.expectEqual(@as(u8, 'K'), sequence.data[5]);
}

test "KeySequence.init with numbers" {
    const sequence = try KeySequence.init("123");

    try testing.expectEqual(@as(u32, 3), sequence.len);
    try testing.expectEqual(@as(u8, '1'), sequence.data[0]);
    try testing.expectEqual(@as(u8, '2'), sequence.data[1]);
    try testing.expectEqual(@as(u8, '3'), sequence.data[2]);
}

test "KeySequence.init with single character" {
    const sequence = try KeySequence.init("a");

    try testing.expectEqual(@as(u32, 1), sequence.len);
    try testing.expectEqual(@as(u8, 'A'), sequence.data[0]);
}

test "KeySequence.init with empty string fails" {
    try testing.expectError(ConfigError.InvalidKey, KeySequence.init(""));
}

test "KeySequence.init with too long string fails" {
    const long_string = "a" ** 33;

    try testing.expectError(ConfigError.SequenceTooLong, KeySequence.init(long_string));
}

test "KeySequence.init with max length string" {
    const max_string = "a" ** 32;
    const sequence = try KeySequence.init(max_string);

    try testing.expectEqual(@as(u32, 32), sequence.len);
}

test "KeySequence.toSlice" {
    const sequence = try KeySequence.init("TEST");
    const slice = sequence.toSlice();

    try testing.expectEqual(@as(usize, 4), slice.len);
    try testing.expectEqual(@as(u8, 'T'), slice[0]);
    try testing.expectEqual(@as(u8, 'E'), slice[1]);
    try testing.expectEqual(@as(u8, 'S'), slice[2]);
    try testing.expectEqual(@as(u8, 'T'), slice[3]);
}

test "KeyCombination.matches with exact match" {
    const combination = KeyCombination{
        .modifier = .{ .ctrl = true, .alt = true },
        .key = 'L',
    };

    const modifier = keycode.ModifierSet{ .ctrl = true, .alt = true };

    try testing.expect(combination.matches('L', modifier));
}

test "KeyCombination.matches with wrong key" {
    const combination = KeyCombination{
        .modifier = .{ .ctrl = true, .alt = true },
        .key = 'L',
    };

    const modifier = keycode.ModifierSet{ .ctrl = true, .alt = true };

    try testing.expect(!combination.matches('K', modifier));
}

test "KeyCombination.matches with wrong modifier" {
    const combination = KeyCombination{
        .modifier = .{ .ctrl = true, .alt = true },
        .key = 'L',
    };

    const modifier = keycode.ModifierSet{ .ctrl = true, .alt = false };

    try testing.expect(!combination.matches('L', modifier));
}

test "KeyCombination.matches with no modifiers" {
    const combination = KeyCombination{
        .modifier = .{},
        .key = 'A',
    };

    const modifier = keycode.ModifierSet{};

    try testing.expect(combination.matches('A', modifier));
}

test "KeyCombination.matches with extra modifiers pressed" {
    const combination = KeyCombination{
        .modifier = .{ .ctrl = true },
        .key = 'A',
    };

    const modifier = keycode.ModifierSet{ .ctrl = true, .shift = true };

    try testing.expect(!combination.matches('A', modifier));
}

test "Config.init creates default configuration" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    try testing.expect(cfg.is_keyboard_locked);
    try testing.expect(!cfg.is_mouse_locked);
    try testing.expect(cfg.show_notification);
    try testing.expectEqual(@as(u32, 0), cfg.remap_count);
    try testing.expectEqual(@as(u32, 0), cfg.disabled_count);
}

test "Config.init default lock shortcut is Ctrl+Alt+L" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    try testing.expectEqual(ShortcutType.combination, std.meta.activeTag(cfg.lock_shortcut));

    const combination = cfg.lock_shortcut.combination;

    try testing.expect(combination.modifier.ctrl);
    try testing.expect(combination.modifier.alt);
    try testing.expect(!combination.modifier.shift);
    try testing.expect(!combination.modifier.win);
    try testing.expectEqual(@as(u32, 'L'), combination.key);
}

test "Config.init default unlock shortcut is UNLOCK sequence" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    try testing.expectEqual(ShortcutType.sequence, std.meta.activeTag(cfg.unlock_shortcut));

    const sequence = cfg.unlock_shortcut.sequence;

    try testing.expectEqual(@as(u32, 6), sequence.len);
    try testing.expectEqualStrings("UNLOCK", sequence.toSlice());
}

test "Config.reset restores defaults" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    cfg.is_keyboard_locked = false;
    cfg.is_mouse_locked = true;
    cfg.show_notification = false;
    cfg.remap_count = 5;
    cfg.disabled_count = 3;

    cfg.reset();

    try testing.expect(cfg.is_keyboard_locked);
    try testing.expect(!cfg.is_mouse_locked);
    try testing.expect(cfg.show_notification);
    try testing.expectEqual(@as(u32, 0), cfg.remap_count);
    try testing.expectEqual(@as(u32, 0), cfg.disabled_count);
}

test "Config.parse with minimal config" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    const content =
        \\.{
        \\    .is_keyboard_locked = false,
        \\    .is_mouse_locked = true,
        \\    .show_notification = false,
        \\}
    ;

    try cfg.parse(content);

    try testing.expect(!cfg.is_keyboard_locked);
    try testing.expect(cfg.is_mouse_locked);
    try testing.expect(!cfg.show_notification);
}

test "Config.parse with lock combination shortcut" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    const content =
        \\.{
        \\    .is_keyboard_locked = true,
        \\    .is_mouse_locked = false,
        \\    .show_notification = true,
        \\    .lock = .{
        \\        .modifiers = .{ "ctrl", "shift" },
        \\        .key = "l",
        \\    },
        \\}
    ;

    try cfg.parse(content);

    try testing.expectEqual(ShortcutType.combination, std.meta.activeTag(cfg.lock_shortcut));

    const combination = cfg.lock_shortcut.combination;

    try testing.expect(combination.modifier.ctrl);
    try testing.expect(!combination.modifier.alt);
    try testing.expect(combination.modifier.shift);
    try testing.expect(!combination.modifier.win);
    try testing.expectEqual(@as(u32, 'L'), combination.key);
}

test "Config.parse with unlock sequence shortcut" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    const content =
        \\.{
        \\    .is_keyboard_locked = true,
        \\    .is_mouse_locked = false,
        \\    .show_notification = true,
        \\    .unlock = .{
        \\        .sequence = "PASSWORD",
        \\    },
        \\}
    ;

    try cfg.parse(content);

    try testing.expectEqual(ShortcutType.sequence, std.meta.activeTag(cfg.unlock_shortcut));

    const sequence = cfg.unlock_shortcut.sequence;

    try testing.expectEqual(@as(u32, 8), sequence.len);
    try testing.expectEqualStrings("PASSWORD", sequence.toSlice());
}

test "Config.parse with function key" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    const content =
        \\.{
        \\    .is_keyboard_locked = true,
        \\    .is_mouse_locked = false,
        \\    .show_notification = true,
        \\    .lock = .{
        \\        .modifiers = .{ "ctrl" },
        \\        .key = "f1",
        \\    },
        \\}
    ;

    try cfg.parse(content);

    try testing.expectEqual(ShortcutType.combination, std.meta.activeTag(cfg.lock_shortcut));

    const combination = cfg.lock_shortcut.combination;

    try testing.expectEqual(keycode.VirtualKey.f1, combination.key);
}

test "Config.parse with remap entries" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    const content =
        \\.{
        \\    .is_keyboard_locked = true,
        \\    .is_mouse_locked = false,
        \\    .show_notification = true,
        \\    .remap = .{
        \\        .{
        \\            .from = .{ .modifiers = .{ "win" }, .key = "e" },
        \\            .to = .{ .modifiers = .{ "ctrl" }, .key = "e" },
        \\        },
        \\    },
        \\}
    ;

    try cfg.parse(content);

    try testing.expectEqual(@as(u32, 1), cfg.remap_count);

    const entry = cfg.remap_entries[0];

    try testing.expect(entry.from.modifier.win);
    try testing.expectEqual(@as(u32, 'E'), entry.from.key);
    try testing.expect(entry.to.modifier.ctrl);
    try testing.expectEqual(@as(u32, 'E'), entry.to.key);
}

test "Config.parse with disabled entries" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    const content =
        \\.{
        \\    .is_keyboard_locked = true,
        \\    .is_mouse_locked = false,
        \\    .show_notification = true,
        \\    .disabled = .{
        \\        .{ .modifiers = .{ "win" }, .key = "l" },
        \\        .{ .modifiers = .{ "win" }, .key = "d" },
        \\    },
        \\}
    ;

    try cfg.parse(content);

    try testing.expectEqual(@as(u32, 2), cfg.disabled_count);

    try testing.expect(cfg.disabled_entries[0].modifier.win);
    try testing.expectEqual(@as(u32, 'L'), cfg.disabled_entries[0].key);

    try testing.expect(cfg.disabled_entries[1].modifier.win);
    try testing.expectEqual(@as(u32, 'D'), cfg.disabled_entries[1].key);
}

test "Config.isDisabled returns true for disabled key" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    cfg.disabled_entries[0] = KeyCombination{
        .modifier = .{ .win = true },
        .key = 'L',
    };
    cfg.disabled_count = 1;

    const modifier = keycode.ModifierSet{ .win = true };

    try testing.expect(cfg.isDisabled('L', modifier));
}

test "Config.isDisabled returns false for enabled key" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    cfg.disabled_entries[0] = KeyCombination{
        .modifier = .{ .win = true },
        .key = 'L',
    };
    cfg.disabled_count = 1;

    const modifier = keycode.ModifierSet{ .win = true };

    try testing.expect(!cfg.isDisabled('K', modifier));
}

test "Config.isDisabled returns false when no disabled entries" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    const modifier = keycode.ModifierSet{ .win = true };

    try testing.expect(!cfg.isDisabled('L', modifier));
}

test "Config.findRemap returns target for matching source" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    cfg.remap_entries[0] = Remap{
        .from = KeyCombination{
            .modifier = .{ .win = true },
            .key = 'E',
        },
        .to = KeyCombination{
            .modifier = .{ .ctrl = true },
            .key = 'E',
        },
    };
    cfg.remap_count = 1;

    const modifier = keycode.ModifierSet{ .win = true };
    const result = cfg.findRemap('E', modifier);

    try testing.expect(result != null);
    try testing.expect(result.?.modifier.ctrl);
    try testing.expectEqual(@as(u32, 'E'), result.?.key);
}

test "Config.findRemap returns null for non-matching source" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    cfg.remap_entries[0] = Remap{
        .from = KeyCombination{
            .modifier = .{ .win = true },
            .key = 'E',
        },
        .to = KeyCombination{
            .modifier = .{ .ctrl = true },
            .key = 'E',
        },
    };
    cfg.remap_count = 1;

    const modifier = keycode.ModifierSet{ .win = true };
    const result = cfg.findRemap('F', modifier);

    try testing.expect(result == null);
}

test "Config.findRemap returns null when no remap entries" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    const modifier = keycode.ModifierSet{ .win = true };
    const result = cfg.findRemap('E', modifier);

    try testing.expect(result == null);
}

test "Config.findRemapEntry returns full entry" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    cfg.remap_entries[0] = Remap{
        .from = KeyCombination{
            .modifier = .{ .win = true },
            .key = 'E',
        },
        .to = KeyCombination{
            .modifier = .{ .ctrl = true },
            .key = 'E',
        },
    };
    cfg.remap_count = 1;

    const modifier = keycode.ModifierSet{ .win = true };
    const result = cfg.findRemapEntry('E', modifier);

    try testing.expect(result != null);
    try testing.expect(result.?.from.modifier.win);
    try testing.expectEqual(@as(u32, 'E'), result.?.from.key);
    try testing.expect(result.?.to.modifier.ctrl);
    try testing.expectEqual(@as(u32, 'E'), result.?.to.key);
}

test "Config.getRemapSlice returns correct slice" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    cfg.remap_entries[0] = Remap{
        .from = KeyCombination{ .key = 'A' },
        .to = KeyCombination{ .key = 'B' },
    };
    cfg.remap_entries[1] = Remap{
        .from = KeyCombination{ .key = 'C' },
        .to = KeyCombination{ .key = 'D' },
    };
    cfg.remap_count = 2;

    const slice = cfg.getRemapSlice();

    try testing.expectEqual(@as(usize, 2), slice.len);
    try testing.expectEqual(@as(u32, 'A'), slice[0].from.key);
    try testing.expectEqual(@as(u32, 'C'), slice[1].from.key);
}

test "Config.getDisabledSlice returns correct slice" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    cfg.disabled_entries[0] = KeyCombination{ .key = 'A' };
    cfg.disabled_entries[1] = KeyCombination{ .key = 'B' };
    cfg.disabled_entries[2] = KeyCombination{ .key = 'C' };
    cfg.disabled_count = 3;

    const slice = cfg.getDisabledSlice();

    try testing.expectEqual(@as(usize, 3), slice.len);
    try testing.expectEqual(@as(u32, 'A'), slice[0].key);
    try testing.expectEqual(@as(u32, 'B'), slice[1].key);
    try testing.expectEqual(@as(u32, 'C'), slice[2].key);
}

test "Config.getLockSequence for combination shortcut" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    cfg.lock_shortcut = .{
        .combination = .{
            .modifier = .{ .ctrl = true, .alt = true },
            .key = 'L',
        },
    };

    const sequence = cfg.getLockSequence();

    try testing.expect(sequence != null);
    try testing.expectEqual(@as(usize, 3), sequence.?.len);
}

test "Config.getLockSequence for sequence shortcut" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    cfg.lock_shortcut = .{
        .sequence = try KeySequence.init("LOCK"),
    };

    const sequence = cfg.getLockSequence();

    try testing.expect(sequence != null);
    try testing.expectEqual(@as(usize, 4), sequence.?.len);
    try testing.expectEqualStrings("LOCK", sequence.?);
}

test "Config.getUnlockSequence for combination shortcut" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    cfg.unlock_shortcut = .{
        .combination = .{
            .modifier = .{ .ctrl = true },
            .key = 'U',
        },
    };

    const sequence = cfg.getUnlockSequence();

    try testing.expect(sequence != null);
    try testing.expectEqual(@as(usize, 2), sequence.?.len);
}

test "Config.getUnlockSequence for sequence shortcut" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    cfg.unlock_shortcut = .{
        .sequence = try KeySequence.init("OPEN"),
    };

    const sequence = cfg.getUnlockSequence();

    try testing.expect(sequence != null);
    try testing.expectEqual(@as(usize, 4), sequence.?.len);
    try testing.expectEqualStrings("OPEN", sequence.?);
}

test "Config.getConfigPath returns null when not loaded" {
    var cfg = Config.init(testing.allocator);

    defer cfg.deinit();

    try testing.expect(cfg.getConfigPath() == null);
}
