const std = @import("std");
const testing = std.testing;

const LockerError = @import("error.zig").LockerError;

pub const CircularBuffer = struct {
    storage: []u8,
    capacity: usize,
    start: usize,
    end: usize,
    allocator: std.mem.Allocator,
    arena: ?std.heap.ArenaAllocator = null,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !CircularBuffer {
        if (capacity == 0 or capacity >= 1024) return LockerError.InvalidCapacity;

        const storage = try allocator.alloc(u8, capacity);
        @memset(storage, 0);

        return CircularBuffer{
            .storage = storage,
            .capacity = capacity,
            .start = 0,
            .end = 0,
            .allocator = allocator,
            .arena = null,
        };
    }

    pub fn deinit(self: *CircularBuffer) void {
        self.allocator.free(self.storage);

        if (self.arena) |*arena| {
            arena.deinit();
            self.arena = null;
        }

        self.storage = &[_]u8{};
        self.capacity = 0;
        self.start = 0;
        self.end = 0;
    }

    pub fn push(self: *CircularBuffer, value: u8) void {
        self.storage[self.end] = value;
        self.end = (self.end + 1) % self.capacity;

        if (self.end == self.start) {
            self.start = (self.start + 1) % self.capacity;
        }

        if (self.arena) |*arena| {
            _ = arena.reset(.retain_capacity);
        }
    }

    pub fn asSlice(self: *CircularBuffer) ![]u8 {
        if (self.start == self.end) return LockerError.EmptyBuffer;

        if (self.arena == null) {
            self.arena = std.heap.ArenaAllocator.init(self.allocator);
        }

        const arena = self.arena.?.allocator();

        if (self.end > self.start) {
            const length = self.end - self.start;
            const result = try arena.alloc(u8, length);
            std.mem.copyForwards(u8, result, self.storage[self.start..self.end]);
            return result;
        }

        const primary = self.capacity - self.start;
        const secondary = self.end;
        const total = primary + secondary;

        const result = try arena.alloc(u8, total);
        std.mem.copyForwards(u8, result[0..primary], self.storage[self.start..]);
        std.mem.copyForwards(u8, result[primary..], self.storage[0..self.end]);

        return result;
    }

    pub fn resetArena(self: *CircularBuffer) void {
        if (self.arena) |*arena| {
            _ = arena.reset(.retain_capacity);
        }
    }

    pub fn isMatch(self: *const CircularBuffer, pattern: []const u8) !bool {
        if (pattern.len == 0) return LockerError.InvalidCapacity;
        if (pattern.len > self.capacity) return LockerError.PatternTooLarge;

        const instance: *CircularBuffer = @constCast(self);
        const data = instance.asSlice() catch return false;

        if (data.len < pattern.len) {
            return false;
        }

        const offset = data.len - pattern.len;
        const segment = data[offset..];

        return std.mem.eql(u8, segment, pattern);
    }
};

test "Initialization with valid capacity" {
    var buffer = try CircularBuffer.init(testing.allocator, 8);
    defer buffer.deinit();

    try testing.expectEqual(@as(usize, 8), buffer.capacity);
    try testing.expectEqual(@as(usize, 0), buffer.start);
    try testing.expectEqual(@as(usize, 0), buffer.end);
    try testing.expectEqualSlices(u8, &[_]u8{0} ** 8, buffer.storage);
}

test "Initialization with invalid capacity" {
    try testing.expectError(LockerError.InvalidCapacity, CircularBuffer.init(testing.allocator, 0));
    try testing.expectError(LockerError.InvalidCapacity, CircularBuffer.init(testing.allocator, 1024));
}

test "Push and basic wrap-around" {
    var buffer = try CircularBuffer.init(testing.allocator, 3);
    defer buffer.deinit();

    buffer.push('a');
    try testing.expectEqual(@as(usize, 0), buffer.start);
    try testing.expectEqual(@as(usize, 1), buffer.end);

    buffer.push('b');
    try testing.expectEqual(@as(usize, 0), buffer.start);
    try testing.expectEqual(@as(usize, 2), buffer.end);

    buffer.push('c');
    try testing.expectEqual(@as(usize, 1), buffer.start);
    try testing.expectEqual(@as(usize, 0), buffer.end);

    buffer.push('d');
    try testing.expectEqual(@as(usize, 2), buffer.start);
    try testing.expectEqual(@as(usize, 1), buffer.end);
}

test "asSlice with basic data" {
    var buffer = try CircularBuffer.init(testing.allocator, 5);
    defer buffer.deinit();

    buffer.push('a');
    buffer.push('b');
    buffer.push('c');

    const slice = try buffer.asSlice();
    try testing.expectEqualSlices(u8, "abc", slice);
}

test "asSlice with empty buffer" {
    var buffer = try CircularBuffer.init(testing.allocator, 5);
    defer buffer.deinit();

    try testing.expectError(LockerError.EmptyBuffer, buffer.asSlice());
}

test "asSlice with wrapped data" {
    var buffer = try CircularBuffer.init(testing.allocator, 3);
    defer buffer.deinit();

    buffer.push('a');
    buffer.push('b');
    buffer.push('c');
    buffer.push('d');

    const slice = try buffer.asSlice();
    try testing.expectEqualSlices(u8, "cd", slice);
}

test "isMatch with suffix matching" {
    var buffer = try CircularBuffer.init(testing.allocator, 5);
    defer buffer.deinit();

    buffer.push('h');
    buffer.push('e');
    buffer.push('l');
    buffer.push('l');
    buffer.push('o');

    try testing.expectEqual(@as(usize, 1), buffer.start);
    try testing.expectEqual(@as(usize, 0), buffer.end);

    try testing.expect(try buffer.isMatch("o"));
    try testing.expect(try buffer.isMatch("lo"));
    try testing.expect(try buffer.isMatch("llo"));
    try testing.expect(try buffer.isMatch("ello"));
    try testing.expect(!try buffer.isMatch("hello"));
}

test "isMatch with wrapped data" {
    var buffer = try CircularBuffer.init(testing.allocator, 3);
    defer buffer.deinit();

    buffer.push('a');
    buffer.push('b');
    buffer.push('c');
    buffer.push('d');

    try testing.expect(try buffer.isMatch("d"));
    try testing.expect(try buffer.isMatch("cd"));
    try testing.expect(!try buffer.isMatch("bcd"));
}

test "isMatch with empty pattern" {
    var buffer = try CircularBuffer.init(testing.allocator, 3);
    defer buffer.deinit();

    buffer.push('a');

    try testing.expectError(LockerError.InvalidCapacity, buffer.isMatch(""));
}

test "isMatch with pattern too large" {
    var buffer = try CircularBuffer.init(testing.allocator, 3);
    defer buffer.deinit();

    buffer.push('a');

    try testing.expectError(LockerError.PatternTooLarge, buffer.isMatch("abcd"));
}

test "resetArena functionality" {
    var buffer = try CircularBuffer.init(testing.allocator, 3);
    defer buffer.deinit();

    buffer.push('a');
    buffer.push('b');

    _ = try buffer.asSlice();
    try testing.expect(buffer.arena != null);

    buffer.resetArena();
    try testing.expect(buffer.arena != null);
}
