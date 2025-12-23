const std = @import("std");
const testing = std.testing;

const LockerError = @import("error.zig").LockerError;

pub const CircularBuffer = struct {
    const capacity_min: u32 = 1;
    const capacity_max: u32 = 1023;

    storage: [capacity_max]u8 = [_]u8{0} ** capacity_max,
    capacity: u32,
    start: u32 = 0,
    end: u32 = 0,

    pub fn init(capacity: u32) LockerError!CircularBuffer {
        if (capacity < capacity_min) {
            return LockerError.InvalidCapacity;
        }

        if (capacity > capacity_max) {
            return LockerError.InvalidCapacity;
        }

        std.debug.assert(capacity >= capacity_min);
        std.debug.assert(capacity <= capacity_max);

        return CircularBuffer{ .capacity = capacity };
    }

    pub fn get(self: *const CircularBuffer, index: u32) ?u8 {
        std.debug.assert(self.capacity >= capacity_min);
        std.debug.assert(self.capacity <= capacity_max);
        std.debug.assert(self.end < self.capacity);
        std.debug.assert(self.start < self.capacity);

        const len = self.length();

        std.debug.assert(len < self.capacity);

        if (index >= len) {
            return null;
        }

        std.debug.assert(index < len);
        std.debug.assert(index < self.capacity);

        std.debug.assert(self.capacity > 0);

        const position = (self.start + index) % self.capacity;

        std.debug.assert(position < self.capacity);
        std.debug.assert(position <= capacity_max);

        return self.storage[position];
    }

    pub fn isEmpty(self: *const CircularBuffer) bool {
        std.debug.assert(self.capacity >= capacity_min);
        std.debug.assert(self.capacity <= capacity_max);
        std.debug.assert(self.end < self.capacity);
        std.debug.assert(self.start < self.capacity);

        const result = self.start == self.end;

        if (result) {
            std.debug.assert(self.length() == 0);
        } else {
            std.debug.assert(self.length() > 0);
        }

        return result;
    }

    pub fn isMatch(self: *const CircularBuffer, pattern: []const u8) LockerError!bool {
        std.debug.assert(self.capacity >= capacity_min);
        std.debug.assert(self.capacity <= capacity_max);
        std.debug.assert(self.end < self.capacity);
        std.debug.assert(self.start < self.capacity);

        const pattern_len: u32 = @intCast(pattern.len);

        if (pattern_len == 0) {
            return LockerError.InvalidCapacity;
        }

        if (pattern_len > self.capacity) {
            return LockerError.PatternTooLarge;
        }

        std.debug.assert(pattern_len > 0);
        std.debug.assert(pattern_len <= self.capacity);
        std.debug.assert(pattern_len <= capacity_max);

        const len = self.length();

        std.debug.assert(len < self.capacity);
        std.debug.assert(len <= capacity_max);

        if (len < pattern_len) {
            return false;
        }

        std.debug.assert(len >= pattern_len);

        var index: u32 = pattern_len;
        var cursor: u32 = self.end;
        var iteration: u32 = 0;

        while (index > 0) {
            std.debug.assert(iteration < pattern_len);
            std.debug.assert(iteration <= capacity_max);

            index -= 1;

            if (cursor == 0) {
                std.debug.assert(self.capacity > 0);

                cursor = self.capacity - 1;
            } else {
                cursor = cursor - 1;
            }

            std.debug.assert(cursor < self.capacity);
            std.debug.assert(cursor <= capacity_max);
            std.debug.assert(index < pattern_len);
            std.debug.assert(index <= capacity_max);

            if (self.storage[cursor] != pattern[index]) {
                return false;
            }

            iteration += 1;
        }

        std.debug.assert(iteration == pattern_len);
        std.debug.assert(iteration <= capacity_max);
        std.debug.assert(index == 0);

        return true;
    }

    pub fn length(self: *const CircularBuffer) u32 {
        std.debug.assert(self.capacity >= capacity_min);
        std.debug.assert(self.capacity <= capacity_max);
        std.debug.assert(self.end < self.capacity);
        std.debug.assert(self.start < self.capacity);

        var result: u32 = 0;

        if (self.end >= self.start) {
            result = self.end - self.start;
        } else {
            result = self.capacity - self.start + self.end;
        }

        std.debug.assert(result < self.capacity);
        std.debug.assert(result <= capacity_max);

        return result;
    }

    pub fn push(self: *CircularBuffer, value: u8) void {
        std.debug.assert(self.capacity >= capacity_min);
        std.debug.assert(self.capacity <= capacity_max);
        std.debug.assert(self.end < self.capacity);
        std.debug.assert(self.start < self.capacity);
        std.debug.assert(self.start != self.end or self.isEmpty());

        self.storage[self.end] = value;

        std.debug.assert(self.capacity > 0);

        const next_end = (self.end + 1) % self.capacity;

        std.debug.assert(next_end < self.capacity);
        std.debug.assert(next_end <= capacity_max);

        self.end = next_end;

        if (self.end == self.start) {
            std.debug.assert(self.capacity > 0);

            const next_start = (self.start + 1) % self.capacity;

            std.debug.assert(next_start < self.capacity);
            std.debug.assert(next_start <= capacity_max);

            self.start = next_start;
        }

        std.debug.assert(self.end < self.capacity);
        std.debug.assert(self.start < self.capacity);
        std.debug.assert(self.end <= capacity_max);
        std.debug.assert(self.start <= capacity_max);
    }
};

test "Initialization with valid capacity" {
    const buffer = try CircularBuffer.init(8);

    try testing.expectEqual(@as(u32, 8), buffer.capacity);
    try testing.expectEqual(@as(u32, 0), buffer.start);
    try testing.expectEqual(@as(u32, 0), buffer.end);
}

test "Initialization with invalid capacity" {
    try testing.expectError(LockerError.InvalidCapacity, CircularBuffer.init(0));
    try testing.expectError(LockerError.InvalidCapacity, CircularBuffer.init(1024));
}

test "Push and basic wrap-around" {
    var buffer = try CircularBuffer.init(3);

    buffer.push('a');
    try testing.expectEqual(@as(u32, 0), buffer.start);
    try testing.expectEqual(@as(u32, 1), buffer.end);

    buffer.push('b');
    try testing.expectEqual(@as(u32, 0), buffer.start);
    try testing.expectEqual(@as(u32, 2), buffer.end);

    buffer.push('c');
    try testing.expectEqual(@as(u32, 1), buffer.start);
    try testing.expectEqual(@as(u32, 0), buffer.end);

    buffer.push('d');
    try testing.expectEqual(@as(u32, 2), buffer.start);
    try testing.expectEqual(@as(u32, 1), buffer.end);
}

test "length calculation" {
    var buffer = try CircularBuffer.init(5);

    try testing.expectEqual(@as(u32, 0), buffer.length());

    buffer.push('a');
    try testing.expectEqual(@as(u32, 1), buffer.length());

    buffer.push('b');
    buffer.push('c');
    try testing.expectEqual(@as(u32, 3), buffer.length());

    buffer.push('d');
    buffer.push('e');
    buffer.push('f');
    try testing.expectEqual(@as(u32, 4), buffer.length());
}

test "get element by index" {
    var buffer = try CircularBuffer.init(5);

    buffer.push('a');
    buffer.push('b');
    buffer.push('c');

    try testing.expectEqual(@as(?u8, 'a'), buffer.get(0));
    try testing.expectEqual(@as(?u8, 'b'), buffer.get(1));
    try testing.expectEqual(@as(?u8, 'c'), buffer.get(2));
    try testing.expectEqual(@as(?u8, null), buffer.get(3));
}

test "get element with wrapped data" {
    var buffer = try CircularBuffer.init(3);

    buffer.push('a');
    buffer.push('b');
    buffer.push('c');
    buffer.push('d');

    try testing.expectEqual(@as(?u8, 'c'), buffer.get(0));
    try testing.expectEqual(@as(?u8, 'd'), buffer.get(1));
    try testing.expectEqual(@as(?u8, null), buffer.get(2));
}

test "isEmpty" {
    var buffer = try CircularBuffer.init(5);

    try testing.expect(buffer.isEmpty());

    buffer.push('a');
    try testing.expect(!buffer.isEmpty());
}

test "isMatch with suffix matching" {
    var buffer = try CircularBuffer.init(5);

    buffer.push('h');
    buffer.push('e');
    buffer.push('l');
    buffer.push('l');
    buffer.push('o');

    try testing.expectEqual(@as(u32, 1), buffer.start);
    try testing.expectEqual(@as(u32, 0), buffer.end);

    try testing.expect(try buffer.isMatch("o"));
    try testing.expect(try buffer.isMatch("lo"));
    try testing.expect(try buffer.isMatch("llo"));
    try testing.expect(try buffer.isMatch("ello"));
    try testing.expect(!try buffer.isMatch("hello"));
}

test "isMatch with wrapped data" {
    var buffer = try CircularBuffer.init(3);

    buffer.push('a');
    buffer.push('b');
    buffer.push('c');
    buffer.push('d');

    try testing.expect(try buffer.isMatch("d"));
    try testing.expect(try buffer.isMatch("cd"));
    try testing.expect(!try buffer.isMatch("bcd"));
}

test "isMatch with empty pattern" {
    var buffer = try CircularBuffer.init(3);

    buffer.push('a');

    try testing.expectError(LockerError.InvalidCapacity, buffer.isMatch(""));
}

test "isMatch with pattern too large" {
    var buffer = try CircularBuffer.init(3);

    buffer.push('a');

    try testing.expectError(LockerError.PatternTooLarge, buffer.isMatch("abcd"));
}

test "isMatch with empty buffer" {
    var buffer = try CircularBuffer.init(5);

    try testing.expect(!try buffer.isMatch("abc"));
}

test "isMatch with exact capacity match" {
    var buffer = try CircularBuffer.init(4);

    buffer.push('a');
    buffer.push('b');
    buffer.push('c');

    try testing.expect(try buffer.isMatch("abc"));
    try testing.expect(!try buffer.isMatch("xbc"));
    try testing.expect(!try buffer.isMatch("abx"));
}

test "isMatch after multiple wraparounds" {
    var buffer = try CircularBuffer.init(3);

    buffer.push('a');
    buffer.push('b');
    buffer.push('c');
    buffer.push('d');
    buffer.push('e');
    buffer.push('f');
    buffer.push('g');

    try testing.expect(try buffer.isMatch("fg"));
    try testing.expect(!try buffer.isMatch("ef"));
}
