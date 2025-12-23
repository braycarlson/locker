const std = @import("std");
const win32 = @import("win32").everything;

const keycode = @import("keycode.zig");
const config = @import("../config.zig");

pub const shortcut_flag: usize = 0x101;

const input_keyboard: u32 = 1;
const keyeventf_extendedkey: u32 = 0x0001;
const keyeventf_keyup: u32 = 0x0002;
const dummy_key: u16 = 0xFF;
const input_max: u32 = 16;
const modifier_max: u32 = 4;

const KeyboardInput = extern struct {
    virtual_key: u16,
    scan_code: u16,
    flag: u32,
    time: u32,
    extra_info: usize,
};

const Input = extern struct {
    type: u32,
    padding: u32 = 0,
    data: extern union {
        keyboard: KeyboardInput,
        padding: [32]u8,
    },

    fn keyboard(virtual_key: u16, flag: u32, extra_info: usize) Input {
        std.debug.assert(virtual_key > 0);

        const scan_code: u16 = @truncate(win32.MapVirtualKeyW(virtual_key, 0));

        return .{
            .type = input_keyboard,
            .data = .{ .keyboard = .{
                .virtual_key = virtual_key,
                .scan_code = scan_code,
                .flag = flag,
                .time = 0,
                .extra_info = extra_info,
            } },
        };
    }

    fn dummy(is_key_up: bool) Input {
        var flag: u32 = 0;

        if (is_key_up) {
            flag = keyeventf_keyup;
        }

        return keyboard(dummy_key, flag, shortcut_flag);
    }
};

fn isKeyDown(virtual_key: u32) bool {
    std.debug.assert(virtual_key > 0);

    const state = win32.GetAsyncKeyState(@intCast(virtual_key));

    if (state < 0) {
        return true;
    }

    return false;
}

fn isAnyKeyDown(left_key: u32, right_key: u32) bool {
    std.debug.assert(left_key > 0);
    std.debug.assert(right_key > 0);

    if (isKeyDown(left_key)) {
        return true;
    }

    if (isKeyDown(right_key)) {
        return true;
    }

    return false;
}

fn isModifierInSet(mods: [4]?keycode.Modifier, target_vk: u32) bool {
    std.debug.assert(target_vk > 0);

    var index: u32 = 0;

    while (index < modifier_max) : (index += 1) {
        std.debug.assert(index < modifier_max);

        if (mods[index]) |mod| {
            const mod_vk = mod.toVirtualKey();

            std.debug.assert(mod_vk > 0);

            if (mod_vk == target_vk) {
                return true;
            }
        }
    }

    std.debug.assert(index == modifier_max);

    return false;
}

fn pressModifiers(modifier: [4]?keycode.Modifier, inputs: *[input_max]Input, start_count: u32) u32 {
    std.debug.assert(start_count < input_max);

    var count = start_count;
    var index: u32 = 0;

    while (index < modifier_max) : (index += 1) {
        std.debug.assert(index < modifier_max);

        if (modifier[index]) |value| {
            std.debug.assert(count < input_max);

            const vk = value.toVirtualKey();

            std.debug.assert(vk > 0);

            inputs[count] = Input.keyboard(@truncate(vk), 0, shortcut_flag);
            count += 1;
        }
    }

    std.debug.assert(index == modifier_max);
    std.debug.assert(count >= start_count);
    std.debug.assert(count <= input_max);

    return count;
}

fn pressTargetModifiers(
    from_mods: [4]?keycode.Modifier,
    to_mods: [4]?keycode.Modifier,
    inputs: *[input_max]Input,
    start_count: u32,
) u32 {
    std.debug.assert(start_count < input_max);
    std.debug.assert(start_count >= 2);

    var count = start_count;
    var index: u32 = 0;

    while (index < modifier_max) : (index += 1) {
        std.debug.assert(index < modifier_max);

        if (to_mods[index]) |to_mod| {
            const to_vk = to_mod.toVirtualKey();

            std.debug.assert(to_vk > 0);

            if (!isModifierInSet(from_mods, to_vk)) {
                std.debug.assert(count < input_max);

                inputs[count] = Input.keyboard(@truncate(to_vk), 0, shortcut_flag);
                count += 1;
            }
        }
    }

    std.debug.assert(index == modifier_max);
    std.debug.assert(count >= start_count);
    std.debug.assert(count <= input_max);

    return count;
}

fn releaseModifiers(modifier: [4]?keycode.Modifier, inputs: *[input_max]Input, start_count: u32) u32 {
    std.debug.assert(start_count < input_max);
    std.debug.assert(start_count >= 2);

    var count = start_count;
    var release_idx: u32 = modifier_max;
    var iteration: u32 = 0;

    while (release_idx > 0) : (release_idx -= 1) {
        std.debug.assert(iteration < modifier_max);

        const idx = release_idx - 1;

        std.debug.assert(idx < modifier_max);

        if (modifier[idx]) |value| {
            std.debug.assert(count < input_max);

            const vk = value.toVirtualKey();

            std.debug.assert(vk > 0);

            inputs[count] = Input.keyboard(@truncate(vk), keyeventf_keyup, shortcut_flag);
            count += 1;
        }

        iteration += 1;
    }

    std.debug.assert(iteration == modifier_max);
    std.debug.assert(count >= start_count);
    std.debug.assert(count <= input_max);

    return count;
}

fn releaseSourceModifiers(
    from_mods: [4]?keycode.Modifier,
    to_mods: [4]?keycode.Modifier,
    inputs: *[input_max]Input,
    start_count: u32,
) u32 {
    std.debug.assert(start_count < input_max);
    std.debug.assert(start_count >= 2);

    var count = start_count;
    var release_idx: u32 = modifier_max;
    var iteration: u32 = 0;

    while (release_idx > 0) : (release_idx -= 1) {
        std.debug.assert(iteration < modifier_max);

        const idx = release_idx - 1;

        std.debug.assert(idx < modifier_max);

        if (from_mods[idx]) |from_mod| {
            const from_vk = from_mod.toVirtualKey();

            std.debug.assert(from_vk > 0);

            if (!isModifierInSet(to_mods, from_vk)) {
                std.debug.assert(count < input_max);

                inputs[count] = Input.keyboard(@truncate(from_vk), keyeventf_keyup, shortcut_flag);
                count += 1;
            }
        }

        iteration += 1;
    }

    std.debug.assert(iteration == modifier_max);
    std.debug.assert(count >= start_count);
    std.debug.assert(count <= input_max);

    return count;
}

fn releaseTargetModifiers(
    from_mods: [4]?keycode.Modifier,
    to_mods: [4]?keycode.Modifier,
    inputs: *[input_max]Input,
    start_count: u32,
) u32 {
    std.debug.assert(start_count < input_max);
    std.debug.assert(start_count >= 4);

    var count = start_count;
    var release_idx: u32 = modifier_max;
    var iteration: u32 = 0;

    while (release_idx > 0) : (release_idx -= 1) {
        std.debug.assert(iteration < modifier_max);

        const idx = release_idx - 1;

        std.debug.assert(idx < modifier_max);

        if (to_mods[idx]) |to_mod| {
            const to_vk = to_mod.toVirtualKey();

            std.debug.assert(to_vk > 0);

            if (!isModifierInSet(from_mods, to_vk)) {
                std.debug.assert(count < input_max);

                inputs[count] = Input.keyboard(@truncate(to_vk), keyeventf_keyup, shortcut_flag);
                count += 1;
            }
        }

        iteration += 1;
    }

    std.debug.assert(iteration == modifier_max);
    std.debug.assert(count >= start_count);
    std.debug.assert(count <= input_max);

    return count;
}

fn sendInput(inputs: []Input) void {
    const inputs_len: u32 = @intCast(inputs.len);

    std.debug.assert(inputs_len > 0);
    std.debug.assert(inputs_len <= input_max);

    const result = win32.SendInput(inputs_len, @ptrCast(inputs.ptr), @sizeOf(Input));

    std.debug.assert(result <= inputs_len);
}

pub fn getCurrentModifier() keycode.ModifierSet {
    var result = keycode.ModifierSet{};

    result.ctrl = isAnyKeyDown(keycode.VirtualKey.lcontrol, keycode.VirtualKey.rcontrol);
    result.alt = isAnyKeyDown(keycode.VirtualKey.lmenu, keycode.VirtualKey.rmenu);
    result.shift = isAnyKeyDown(keycode.VirtualKey.lshift, keycode.VirtualKey.rshift);
    result.win = isAnyKeyDown(keycode.VirtualKey.lwin, keycode.VirtualKey.rwin);

    return result;
}

pub fn sendKeyCombination(combination: config.KeyCombination) void {
    std.debug.assert(combination.key > 0);

    var inputs: [input_max]Input = undefined;
    var count: u32 = 0;

    const modifier = combination.modifier.toArray();

    count = pressModifiers(modifier, &inputs, count);

    std.debug.assert(count <= modifier_max);
    std.debug.assert(count < input_max - 1);

    inputs[count] = Input.keyboard(@truncate(combination.key), 0, shortcut_flag);
    count += 1;

    std.debug.assert(count < input_max);

    inputs[count] = Input.keyboard(@truncate(combination.key), keyeventf_keyup, shortcut_flag);
    count += 1;

    std.debug.assert(count <= input_max);

    count = releaseModifiers(modifier, &inputs, count);

    std.debug.assert(count > 0);
    std.debug.assert(count <= input_max);

    sendInput(inputs[0..count]);
}

pub fn sendRemappedShortcut(from: config.KeyCombination, to: config.KeyCombination) void {
    std.debug.assert(from.key > 0);
    std.debug.assert(to.key > 0);

    var inputs: [input_max]Input = undefined;
    var count: u32 = 0;

    const from_mods = from.modifier.toArray();
    const to_mods = to.modifier.toArray();

    std.debug.assert(count < input_max);

    inputs[count] = Input.dummy(false);
    count += 1;

    std.debug.assert(count < input_max);

    inputs[count] = Input.dummy(true);
    count += 1;

    std.debug.assert(count >= 2);
    std.debug.assert(count <= input_max);

    count = releaseSourceModifiers(from_mods, to_mods, &inputs, count);

    std.debug.assert(count >= 2);
    std.debug.assert(count <= input_max);

    count = pressTargetModifiers(from_mods, to_mods, &inputs, count);

    std.debug.assert(count >= 2);
    std.debug.assert(count <= input_max);
    std.debug.assert(count < input_max - 1);

    inputs[count] = Input.keyboard(@truncate(to.key), 0, shortcut_flag);
    count += 1;

    std.debug.assert(count < input_max);

    inputs[count] = Input.keyboard(@truncate(to.key), keyeventf_keyup, shortcut_flag);
    count += 1;

    std.debug.assert(count <= input_max);

    count = releaseTargetModifiers(from_mods, to_mods, &inputs, count);

    std.debug.assert(count > 0);
    std.debug.assert(count <= input_max);

    sendInput(inputs[0..count]);
}

pub fn suppressWindowsKey(windows_key: u32) void {
    const is_lwin = windows_key == keycode.VirtualKey.lwin;
    const is_rwin = windows_key == keycode.VirtualKey.rwin;

    std.debug.assert(is_lwin or is_rwin);

    if (!is_lwin) {
        std.debug.assert(is_rwin);
    }

    if (!is_rwin) {
        std.debug.assert(is_lwin);
    }

    var inputs = [_]Input{
        Input.dummy(false),
        Input.dummy(true),
        Input.keyboard(@truncate(windows_key), keyeventf_extendedkey | keyeventf_keyup, shortcut_flag),
    };

    std.debug.assert(inputs.len == 3);
    std.debug.assert(inputs.len <= input_max);

    sendInput(&inputs);
}
