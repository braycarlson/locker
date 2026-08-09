const std = @import("std");

const nimble = @import("nimble");

const assert = std.debug.assert;

const Client = nimble.remote.Client;

pub const Error = error{
    ConnectFailed,
};

pub const InputThread = struct {
    client: Client,

    pub fn init() InputThread {
        return InputThread{ .client = .{} };
    }

    pub fn deinit(thread: *InputThread) void {
        thread.stop();

        assert(!thread.is_running());
    }

    pub fn start(thread: *InputThread) Error!void {
        thread.client.connect() catch {
            return Error.ConnectFailed;
        };
    }

    pub fn stop(thread: *InputThread) void {
        thread.client.disconnect();

        assert(!thread.is_running());
    }

    pub fn is_running(thread: *const InputThread) bool {
        return thread.client.is_connected();
    }

    pub fn handle(thread: *InputThread) *Client {
        return &thread.client;
    }
};

const testing = std.testing;

test "an input thread starts disconnected" {
    var input = InputThread.init();
    defer input.deinit();

    try testing.expect(!input.is_running());
}

test "stopping an unstarted input thread is inert" {
    var input = InputThread.init();
    defer input.deinit();

    input.stop();

    try testing.expect(!input.is_running());
}
