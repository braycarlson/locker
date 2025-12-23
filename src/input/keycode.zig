const std = @import("std");
const w32 = @import("win32").everything;

pub const Modifier = enum(u8) {
    ctrl = 0,
    alt = 1,
    shift = 2,
    win = 3,

    pub fn fromString(string: []const u8) ?Modifier {
        if (string.len == 0) {
            return null;
        }

        std.debug.assert(string.len > 0);

        const map = std.StaticStringMap(Modifier).initComptime(.{
            .{ "ctrl", .ctrl },
            .{ "control", .ctrl },
            .{ "alt", .alt },
            .{ "shift", .shift },
            .{ "win", .win },
            .{ "windows", .win },
            .{ "meta", .win },
        });

        return map.get(string);
    }

    pub fn toVirtualKey(self: Modifier) u32 {
        std.debug.assert(@intFromEnum(self) <= 3);

        const result = switch (self) {
            .ctrl => VirtualKey.lcontrol,
            .alt => VirtualKey.lmenu,
            .shift => VirtualKey.lshift,
            .win => VirtualKey.lwin,
        };

        std.debug.assert(result > 0);

        return result;
    }
};

pub const ModifierSet = struct {
    ctrl: bool = false,
    alt: bool = false,
    shift: bool = false,
    win: bool = false,

    pub fn eql(self: ModifierSet, other: ModifierSet) bool {
        if (self.ctrl != other.ctrl) {
            return false;
        }

        if (self.alt != other.alt) {
            return false;
        }

        if (self.shift != other.shift) {
            return false;
        }

        if (self.win != other.win) {
            return false;
        }

        return true;
    }

    pub fn toArray(self: ModifierSet) [4]?Modifier {
        return .{
            if (self.ctrl) .ctrl else null,
            if (self.alt) .alt else null,
            if (self.shift) .shift else null,
            if (self.win) .win else null,
        };
    }
};

pub const VirtualKey = struct {
    pub const back: u32 = 0x08;
    pub const tab: u32 = 0x09;
    pub const @"return": u32 = 0x0D;
    pub const shift: u32 = 0x10;
    pub const control: u32 = 0x11;
    pub const menu: u32 = 0x12;
    pub const pause: u32 = 0x13;
    pub const capital: u32 = 0x14;
    pub const escape: u32 = 0x1B;
    pub const space: u32 = 0x20;
    pub const prior: u32 = 0x21;
    pub const next: u32 = 0x22;
    pub const end: u32 = 0x23;
    pub const home: u32 = 0x24;
    pub const left: u32 = 0x25;
    pub const up: u32 = 0x26;
    pub const right: u32 = 0x27;
    pub const down: u32 = 0x28;
    pub const snapshot: u32 = 0x2C;
    pub const insert: u32 = 0x2D;
    pub const delete: u32 = 0x2E;
    pub const lwin: u32 = 0x5B;
    pub const rwin: u32 = 0x5C;
    pub const apps: u32 = 0x5D;
    pub const f1: u32 = 0x70;
    pub const f2: u32 = 0x71;
    pub const f3: u32 = 0x72;
    pub const f4: u32 = 0x73;
    pub const f5: u32 = 0x74;
    pub const f6: u32 = 0x75;
    pub const f7: u32 = 0x76;
    pub const f8: u32 = 0x77;
    pub const f9: u32 = 0x78;
    pub const f10: u32 = 0x79;
    pub const f11: u32 = 0x7A;
    pub const f12: u32 = 0x7B;
    pub const numlock: u32 = 0x90;
    pub const scroll: u32 = 0x91;
    pub const lshift: u32 = 0xA0;
    pub const rshift: u32 = 0xA1;
    pub const lcontrol: u32 = 0xA2;
    pub const rcontrol: u32 = 0xA3;
    pub const lmenu: u32 = 0xA4;
    pub const rmenu: u32 = 0xA5;
    pub const oem_1: u32 = 0xBA;
    pub const oem_plus: u32 = 0xBB;
    pub const oem_comma: u32 = 0xBC;
    pub const oem_minus: u32 = 0xBD;
    pub const oem_period: u32 = 0xBE;
    pub const oem_2: u32 = 0xBF;
    pub const oem_3: u32 = 0xC0;
    pub const oem_4: u32 = 0xDB;
    pub const oem_5: u32 = 0xDC;
    pub const oem_6: u32 = 0xDD;
    pub const oem_7: u32 = 0xDE;

    pub fn fromCode(code: u32) ?[]const u8 {
        if (code == 0) {
            return null;
        }

        std.debug.assert(code > 0);

        if (code >= 'A' and code <= 'Z') {
            return null;
        }

        if (code >= '0' and code <= '9') {
            return null;
        }

        return switch (code) {
            back => "Backspace",
            tab => "Tab",
            @"return" => "Enter",
            shift, lshift, rshift => "Shift",
            control, lcontrol, rcontrol => "Ctrl",
            menu, lmenu, rmenu => "Alt",
            pause => "Pause",
            capital => "CapsLock",
            escape => "Escape",
            space => "Space",
            prior => "PageUp",
            next => "PageDown",
            end => "End",
            home => "Home",
            left => "Left",
            up => "Up",
            right => "Right",
            down => "Down",
            snapshot => "PrintScreen",
            insert => "Insert",
            delete => "Delete",
            lwin, rwin => "Win",
            apps => "Apps",
            f1 => "F1",
            f2 => "F2",
            f3 => "F3",
            f4 => "F4",
            f5 => "F5",
            f6 => "F6",
            f7 => "F7",
            f8 => "F8",
            f9 => "F9",
            f10 => "F10",
            f11 => "F11",
            f12 => "F12",
            numlock => "NumLock",
            scroll => "ScrollLock",
            else => null,
        };
    }

    pub fn fromString(key: []const u8) ?u32 {
        if (key.len == 0) {
            return null;
        }

        std.debug.assert(key.len > 0);

        if (key.len == 1) {
            const character = std.ascii.toUpper(key[0]);

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
        }

        const map = std.StaticStringMap(u32).initComptime(.{
            .{ "backspace", back },
            .{ "tab", tab },
            .{ "enter", @"return" },
            .{ "return", @"return" },
            .{ "pause", pause },
            .{ "capslock", capital },
            .{ "caps", capital },
            .{ "escape", escape },
            .{ "esc", escape },
            .{ "space", space },
            .{ "pageup", prior },
            .{ "pagedown", next },
            .{ "end", end },
            .{ "home", home },
            .{ "left", left },
            .{ "up", up },
            .{ "right", right },
            .{ "down", down },
            .{ "printscreen", snapshot },
            .{ "insert", insert },
            .{ "delete", delete },
            .{ "del", delete },
            .{ "f1", f1 },
            .{ "f2", f2 },
            .{ "f3", f3 },
            .{ "f4", f4 },
            .{ "f5", f5 },
            .{ "f6", f6 },
            .{ "f7", f7 },
            .{ "f8", f8 },
            .{ "f9", f9 },
            .{ "f10", f10 },
            .{ "f11", f11 },
            .{ "f12", f12 },
            .{ "numlock", numlock },
            .{ "scrolllock", scroll },
            .{ "semicolon", oem_1 },
            .{ "equals", oem_plus },
            .{ "plus", oem_plus },
            .{ "comma", oem_comma },
            .{ "minus", oem_minus },
            .{ "period", oem_period },
            .{ "dot", oem_period },
            .{ "slash", oem_2 },
            .{ "backtick", oem_3 },
            .{ "tilde", oem_3 },
            .{ "openbracket", oem_4 },
            .{ "backslash", oem_5 },
            .{ "closebracket", oem_6 },
            .{ "quote", oem_7 },
            .{ "apostrophe", oem_7 },
        });

        return map.get(key);
    }
};

pub fn isModifierKey(virtual_key_code: u32) bool {
    if (virtual_key_code == 0) {
        return false;
    }

    std.debug.assert(virtual_key_code > 0);

    return switch (virtual_key_code) {
        VirtualKey.shift,
        VirtualKey.lshift,
        VirtualKey.rshift,
        VirtualKey.control,
        VirtualKey.lcontrol,
        VirtualKey.rcontrol,
        VirtualKey.menu,
        VirtualKey.lmenu,
        VirtualKey.rmenu,
        VirtualKey.lwin,
        VirtualKey.rwin,
        => true,
        else => false,
    };
}

pub const Keyboard = struct {
    const blocked_key_count: u32 = 3;
    const blocked_message_count: u32 = 2;

    const blocked_key = [blocked_key_count]u32{
        VirtualKey.apps,
        VirtualKey.escape,
        VirtualKey.space,
    };

    const blocked_message = [blocked_message_count]u32{
        w32.WM_KEYDOWN,
        w32.WM_SYSKEYDOWN,
    };

    pub fn isBlockedKey(key: u32) bool {
        if (key == 0) {
            return false;
        }

        std.debug.assert(key > 0);

        var i: u32 = 0;

        while (i < blocked_key_count) : (i += 1) {
            std.debug.assert(i < blocked_key_count);

            if (key == blocked_key[i]) {
                return true;
            }
        }

        std.debug.assert(i == blocked_key_count);

        return false;
    }

    pub fn isBlockedMessage(message: usize) bool {
        const truncated: u32 = @truncate(message);

        var i: u32 = 0;

        while (i < blocked_message_count) : (i += 1) {
            std.debug.assert(i < blocked_message_count);

            if (truncated == blocked_message[i]) {
                return true;
            }
        }

        std.debug.assert(i == blocked_message_count);

        return false;
    }
};

pub const Mouse = struct {
    const blocked_message_count: u32 = 9;

    const blocked_message = [blocked_message_count]u32{
        w32.WM_LBUTTONDOWN,
        w32.WM_MBUTTONDOWN,
        w32.WM_RBUTTONDOWN,
        w32.WM_XBUTTONDOWN,
        w32.WM_LBUTTONUP,
        w32.WM_MBUTTONUP,
        w32.WM_RBUTTONUP,
        w32.WM_XBUTTONUP,
        w32.WM_MOUSEWHEEL,
    };

    pub fn isBlockedMessage(message: usize) bool {
        const truncated: u32 = @truncate(message);

        var i: u32 = 0;

        while (i < blocked_message_count) : (i += 1) {
            std.debug.assert(i < blocked_message_count);

            if (truncated == blocked_message[i]) {
                return true;
            }
        }

        std.debug.assert(i == blocked_message_count);

        return false;
    }
};

const testing = std.testing;

test "Modifier.fromString with valid modifiers" {
    try testing.expectEqual(@as(?Modifier, .ctrl), Modifier.fromString("ctrl"));
    try testing.expectEqual(@as(?Modifier, .ctrl), Modifier.fromString("control"));
    try testing.expectEqual(@as(?Modifier, .alt), Modifier.fromString("alt"));
    try testing.expectEqual(@as(?Modifier, .shift), Modifier.fromString("shift"));
    try testing.expectEqual(@as(?Modifier, .win), Modifier.fromString("win"));
    try testing.expectEqual(@as(?Modifier, .win), Modifier.fromString("windows"));
    try testing.expectEqual(@as(?Modifier, .win), Modifier.fromString("meta"));
}

test "Modifier.fromString with invalid modifiers" {
    try testing.expectEqual(@as(?Modifier, null), Modifier.fromString(""));
    try testing.expectEqual(@as(?Modifier, null), Modifier.fromString("invalid"));
    try testing.expectEqual(@as(?Modifier, null), Modifier.fromString("CTRL"));
    try testing.expectEqual(@as(?Modifier, null), Modifier.fromString("Alt"));
}

test "Modifier.toVirtualKey" {
    try testing.expectEqual(VirtualKey.lcontrol, Modifier.ctrl.toVirtualKey());
    try testing.expectEqual(VirtualKey.lmenu, Modifier.alt.toVirtualKey());
    try testing.expectEqual(VirtualKey.lshift, Modifier.shift.toVirtualKey());
    try testing.expectEqual(VirtualKey.lwin, Modifier.win.toVirtualKey());
}

test "ModifierSet.eql with identical sets" {
    const set1 = ModifierSet{ .ctrl = true, .alt = true, .shift = false, .win = false };
    const set2 = ModifierSet{ .ctrl = true, .alt = true, .shift = false, .win = false };

    try testing.expect(set1.eql(set2));
    try testing.expect(set2.eql(set1));
}

test "ModifierSet.eql with different sets" {
    const set1 = ModifierSet{ .ctrl = true, .alt = true, .shift = false, .win = false };
    const set2 = ModifierSet{ .ctrl = true, .alt = false, .shift = false, .win = false };

    try testing.expect(!set1.eql(set2));
    try testing.expect(!set2.eql(set1));
}

test "ModifierSet.eql with empty sets" {
    const set1 = ModifierSet{};
    const set2 = ModifierSet{};

    try testing.expect(set1.eql(set2));
}

test "ModifierSet.eql with all modifiers" {
    const set1 = ModifierSet{ .ctrl = true, .alt = true, .shift = true, .win = true };
    const set2 = ModifierSet{ .ctrl = true, .alt = true, .shift = true, .win = true };

    try testing.expect(set1.eql(set2));
}

test "ModifierSet.eql ctrl difference" {
    const set1 = ModifierSet{ .ctrl = true };
    const set2 = ModifierSet{ .ctrl = false };

    try testing.expect(!set1.eql(set2));
}

test "ModifierSet.eql shift difference" {
    const set1 = ModifierSet{ .shift = true };
    const set2 = ModifierSet{ .shift = false };

    try testing.expect(!set1.eql(set2));
}

test "ModifierSet.eql win difference" {
    const set1 = ModifierSet{ .win = true };
    const set2 = ModifierSet{ .win = false };

    try testing.expect(!set1.eql(set2));
}

test "ModifierSet.toArray with no modifiers" {
    const set = ModifierSet{};
    const array = set.toArray();

    try testing.expectEqual(@as(?Modifier, null), array[0]);
    try testing.expectEqual(@as(?Modifier, null), array[1]);
    try testing.expectEqual(@as(?Modifier, null), array[2]);
    try testing.expectEqual(@as(?Modifier, null), array[3]);
}

test "ModifierSet.toArray with all modifiers" {
    const set = ModifierSet{ .ctrl = true, .alt = true, .shift = true, .win = true };
    const array = set.toArray();

    try testing.expectEqual(@as(?Modifier, .ctrl), array[0]);
    try testing.expectEqual(@as(?Modifier, .alt), array[1]);
    try testing.expectEqual(@as(?Modifier, .shift), array[2]);
    try testing.expectEqual(@as(?Modifier, .win), array[3]);
}

test "ModifierSet.toArray with some modifiers" {
    const set = ModifierSet{ .ctrl = true, .alt = false, .shift = true, .win = false };
    const array = set.toArray();

    try testing.expectEqual(@as(?Modifier, .ctrl), array[0]);
    try testing.expectEqual(@as(?Modifier, null), array[1]);
    try testing.expectEqual(@as(?Modifier, .shift), array[2]);
    try testing.expectEqual(@as(?Modifier, null), array[3]);
}

test "VirtualKey.fromCode with zero" {
    try testing.expectEqual(@as(?[]const u8, null), VirtualKey.fromCode(0));
}

test "VirtualKey.fromCode with letters" {
    try testing.expectEqual(@as(?[]const u8, null), VirtualKey.fromCode('A'));
    try testing.expectEqual(@as(?[]const u8, null), VirtualKey.fromCode('Z'));
    try testing.expectEqual(@as(?[]const u8, null), VirtualKey.fromCode('M'));
}

test "VirtualKey.fromCode with numbers" {
    try testing.expectEqual(@as(?[]const u8, null), VirtualKey.fromCode('0'));
    try testing.expectEqual(@as(?[]const u8, null), VirtualKey.fromCode('9'));
    try testing.expectEqual(@as(?[]const u8, null), VirtualKey.fromCode('5'));
}

test "VirtualKey.fromCode with special keys" {
    try testing.expectEqualStrings("Backspace", VirtualKey.fromCode(VirtualKey.back).?);
    try testing.expectEqualStrings("Tab", VirtualKey.fromCode(VirtualKey.tab).?);
    try testing.expectEqualStrings("Enter", VirtualKey.fromCode(VirtualKey.@"return").?);
    try testing.expectEqualStrings("Escape", VirtualKey.fromCode(VirtualKey.escape).?);
    try testing.expectEqualStrings("Space", VirtualKey.fromCode(VirtualKey.space).?);
}

test "VirtualKey.fromCode with modifier keys" {
    try testing.expectEqualStrings("Shift", VirtualKey.fromCode(VirtualKey.shift).?);
    try testing.expectEqualStrings("Shift", VirtualKey.fromCode(VirtualKey.lshift).?);
    try testing.expectEqualStrings("Shift", VirtualKey.fromCode(VirtualKey.rshift).?);
    try testing.expectEqualStrings("Ctrl", VirtualKey.fromCode(VirtualKey.control).?);
    try testing.expectEqualStrings("Ctrl", VirtualKey.fromCode(VirtualKey.lcontrol).?);
    try testing.expectEqualStrings("Ctrl", VirtualKey.fromCode(VirtualKey.rcontrol).?);
    try testing.expectEqualStrings("Alt", VirtualKey.fromCode(VirtualKey.menu).?);
    try testing.expectEqualStrings("Alt", VirtualKey.fromCode(VirtualKey.lmenu).?);
    try testing.expectEqualStrings("Alt", VirtualKey.fromCode(VirtualKey.rmenu).?);
}

test "VirtualKey.fromCode with function keys" {
    try testing.expectEqualStrings("F1", VirtualKey.fromCode(VirtualKey.f1).?);
    try testing.expectEqualStrings("F6", VirtualKey.fromCode(VirtualKey.f6).?);
    try testing.expectEqualStrings("F12", VirtualKey.fromCode(VirtualKey.f12).?);
}

test "VirtualKey.fromCode with navigation keys" {
    try testing.expectEqualStrings("Left", VirtualKey.fromCode(VirtualKey.left).?);
    try testing.expectEqualStrings("Up", VirtualKey.fromCode(VirtualKey.up).?);
    try testing.expectEqualStrings("Right", VirtualKey.fromCode(VirtualKey.right).?);
    try testing.expectEqualStrings("Down", VirtualKey.fromCode(VirtualKey.down).?);
    try testing.expectEqualStrings("Home", VirtualKey.fromCode(VirtualKey.home).?);
    try testing.expectEqualStrings("End", VirtualKey.fromCode(VirtualKey.end).?);
    try testing.expectEqualStrings("PageUp", VirtualKey.fromCode(VirtualKey.prior).?);
    try testing.expectEqualStrings("PageDown", VirtualKey.fromCode(VirtualKey.next).?);
}

test "VirtualKey.fromCode with unknown code" {
    try testing.expectEqual(@as(?[]const u8, null), VirtualKey.fromCode(0xFF));
}

test "VirtualKey.fromString with empty string" {
    try testing.expectEqual(@as(?u32, null), VirtualKey.fromString(""));
}

test "VirtualKey.fromString with single lowercase letter" {
    try testing.expectEqual(@as(?u32, 'A'), VirtualKey.fromString("a"));
    try testing.expectEqual(@as(?u32, 'Z'), VirtualKey.fromString("z"));
    try testing.expectEqual(@as(?u32, 'M'), VirtualKey.fromString("m"));
}

test "VirtualKey.fromString with single uppercase letter" {
    try testing.expectEqual(@as(?u32, 'A'), VirtualKey.fromString("A"));
    try testing.expectEqual(@as(?u32, 'Z'), VirtualKey.fromString("Z"));
    try testing.expectEqual(@as(?u32, 'M'), VirtualKey.fromString("M"));
}

test "VirtualKey.fromString with single digit" {
    try testing.expectEqual(@as(?u32, '0'), VirtualKey.fromString("0"));
    try testing.expectEqual(@as(?u32, '9'), VirtualKey.fromString("9"));
    try testing.expectEqual(@as(?u32, '5'), VirtualKey.fromString("5"));
}

test "VirtualKey.fromString with special key names" {
    try testing.expectEqual(@as(?u32, VirtualKey.back), VirtualKey.fromString("backspace"));
    try testing.expectEqual(@as(?u32, VirtualKey.tab), VirtualKey.fromString("tab"));
    try testing.expectEqual(@as(?u32, VirtualKey.@"return"), VirtualKey.fromString("enter"));
    try testing.expectEqual(@as(?u32, VirtualKey.@"return"), VirtualKey.fromString("return"));
    try testing.expectEqual(@as(?u32, VirtualKey.escape), VirtualKey.fromString("escape"));
    try testing.expectEqual(@as(?u32, VirtualKey.escape), VirtualKey.fromString("esc"));
    try testing.expectEqual(@as(?u32, VirtualKey.space), VirtualKey.fromString("space"));
}

test "VirtualKey.fromString with function keys" {
    try testing.expectEqual(@as(?u32, VirtualKey.f1), VirtualKey.fromString("f1"));
    try testing.expectEqual(@as(?u32, VirtualKey.f6), VirtualKey.fromString("f6"));
    try testing.expectEqual(@as(?u32, VirtualKey.f12), VirtualKey.fromString("f12"));
}

test "VirtualKey.fromString with navigation keys" {
    try testing.expectEqual(@as(?u32, VirtualKey.left), VirtualKey.fromString("left"));
    try testing.expectEqual(@as(?u32, VirtualKey.up), VirtualKey.fromString("up"));
    try testing.expectEqual(@as(?u32, VirtualKey.right), VirtualKey.fromString("right"));
    try testing.expectEqual(@as(?u32, VirtualKey.down), VirtualKey.fromString("down"));
    try testing.expectEqual(@as(?u32, VirtualKey.home), VirtualKey.fromString("home"));
    try testing.expectEqual(@as(?u32, VirtualKey.end), VirtualKey.fromString("end"));
    try testing.expectEqual(@as(?u32, VirtualKey.prior), VirtualKey.fromString("pageup"));
    try testing.expectEqual(@as(?u32, VirtualKey.next), VirtualKey.fromString("pagedown"));
}

test "VirtualKey.fromString with punctuation keys" {
    try testing.expectEqual(@as(?u32, VirtualKey.oem_1), VirtualKey.fromString("semicolon"));
    try testing.expectEqual(@as(?u32, VirtualKey.oem_plus), VirtualKey.fromString("equals"));
    try testing.expectEqual(@as(?u32, VirtualKey.oem_plus), VirtualKey.fromString("plus"));
    try testing.expectEqual(@as(?u32, VirtualKey.oem_comma), VirtualKey.fromString("comma"));
    try testing.expectEqual(@as(?u32, VirtualKey.oem_minus), VirtualKey.fromString("minus"));
    try testing.expectEqual(@as(?u32, VirtualKey.oem_period), VirtualKey.fromString("period"));
    try testing.expectEqual(@as(?u32, VirtualKey.oem_period), VirtualKey.fromString("dot"));
    try testing.expectEqual(@as(?u32, VirtualKey.oem_2), VirtualKey.fromString("slash"));
    try testing.expectEqual(@as(?u32, VirtualKey.oem_3), VirtualKey.fromString("backtick"));
    try testing.expectEqual(@as(?u32, VirtualKey.oem_3), VirtualKey.fromString("tilde"));
}

test "VirtualKey.fromString with invalid key name" {
    try testing.expectEqual(@as(?u32, null), VirtualKey.fromString("invalid"));
    try testing.expectEqual(@as(?u32, null), VirtualKey.fromString("ESCAPE"));
    try testing.expectEqual(@as(?u32, null), VirtualKey.fromString("Enter"));
}

test "isModifierKey with modifier keys" {
    try testing.expect(isModifierKey(VirtualKey.shift));
    try testing.expect(isModifierKey(VirtualKey.lshift));
    try testing.expect(isModifierKey(VirtualKey.rshift));
    try testing.expect(isModifierKey(VirtualKey.control));
    try testing.expect(isModifierKey(VirtualKey.lcontrol));
    try testing.expect(isModifierKey(VirtualKey.rcontrol));
    try testing.expect(isModifierKey(VirtualKey.menu));
    try testing.expect(isModifierKey(VirtualKey.lmenu));
    try testing.expect(isModifierKey(VirtualKey.rmenu));
    try testing.expect(isModifierKey(VirtualKey.lwin));
    try testing.expect(isModifierKey(VirtualKey.rwin));
}

test "isModifierKey with non-modifier keys" {
    try testing.expect(!isModifierKey(VirtualKey.@"return"));
    try testing.expect(!isModifierKey(VirtualKey.escape));
    try testing.expect(!isModifierKey(VirtualKey.space));
    try testing.expect(!isModifierKey(VirtualKey.f1));
    try testing.expect(!isModifierKey('A'));
    try testing.expect(!isModifierKey('0'));
}

test "isModifierKey with zero" {
    try testing.expect(!isModifierKey(0));
}

test "Keyboard.isBlockedKey with blocked keys" {
    try testing.expect(Keyboard.isBlockedKey(VirtualKey.apps));
    try testing.expect(Keyboard.isBlockedKey(VirtualKey.escape));
    try testing.expect(Keyboard.isBlockedKey(VirtualKey.space));
}

test "Keyboard.isBlockedKey with non-blocked keys" {
    try testing.expect(!Keyboard.isBlockedKey(VirtualKey.@"return"));
    try testing.expect(!Keyboard.isBlockedKey(VirtualKey.tab));
    try testing.expect(!Keyboard.isBlockedKey('A'));
    try testing.expect(!Keyboard.isBlockedKey(VirtualKey.f1));
}

test "Keyboard.isBlockedKey with zero" {
    try testing.expect(!Keyboard.isBlockedKey(0));
}
