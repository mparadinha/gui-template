const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @import("c.zig");
const Window = @import("Window.zig");
const gl = @import("gl_4v3.zig");
const gfx = @import("graphics.zig");
const math = @import("math.zig");
const vec2 = math.vec2;
const vec4 = math.vec4;
const Font = @import("Font.zig");
const UiContext = @import("UiContext.zig");
const Size = UiContext.Size;

const tracy = @import("../tracy/tracy.zig");

// icon font (and this mapping) was generated using fontello.com
pub const Icons = struct {
    // zig fmt: off
    pub const cancel        = utf8LitFromCodepoint(59392);
    pub const th_list       = utf8LitFromCodepoint(59393);
    pub const search        = utf8LitFromCodepoint(59394);
    pub const plus_circled  = utf8LitFromCodepoint(59395);
    pub const cog           = utf8LitFromCodepoint(59396);
    pub const ok            = utf8LitFromCodepoint(59397);
    pub const circle        = utf8LitFromCodepoint(61713);
    pub const up_open       = utf8LitFromCodepoint(59398);
    pub const right_open    = utf8LitFromCodepoint(59399);
    pub const left_open     = utf8LitFromCodepoint(59400);
    pub const down_open     = utf8LitFromCodepoint(59401);
    pub const plus_squared  = utf8LitFromCodepoint(61694);
    pub const minus_squared = utf8LitFromCodepoint(61766);
    pub const plus          = utf8LitFromCodepoint(59402);
    // zig fmt: on

    fn utf8Len(comptime codepoint: u21) u3 {
        return std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
    }
    fn utf8LitFromCodepoint(comptime codepoint: u21) *const [utf8Len(codepoint):0]u8 {
        comptime {
            var buf: [utf8Len(codepoint):0]u8 = undefined;
            _ = std.unicode.utf8Encode(codepoint, &buf) catch unreachable;
            buf[buf.len] = 0;
            return &buf;
        }
    }
};

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{
        .stack_trace_frames = 8,
        .enable_memory_limit = true,
    }){};
    defer _ = general_purpose_allocator.detectLeaks();
    const allocator = general_purpose_allocator.allocator();

    var width: u32 = 1600;
    var height: u32 = 900;
    var window = try Window.init(allocator, width, height, "gui-template");
    window.finishSetup();
    defer window.deinit();

    // GL state that we never change
    gl.clearColor(0.75, 0.36, 0.38, 1);
    gl.enable(gl.CULL_FACE);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    gl.enable(gl.DEPTH_TEST);
    gl.depthFunc(gl.LEQUAL);
    gl.enable(gl.LINE_SMOOTH);

    var ui = try UiContext.init(allocator, "VictorMono-Regular.ttf", "icons.ttf", &window);
    defer ui.deinit();

    var frame_idx: u64 = 0;
    var last_time: f64 = c.glfwGetTime();

    while (!window.shouldClose()) {
        var frame_arena = std.heap.ArenaAllocator.init(allocator);
        defer frame_arena.deinit();

        const framebuf_size = try window.getFramebufferSize();
        width = framebuf_size[0];
        height = framebuf_size[1];
        gl.viewport(0, 0, @intCast(i32, width), @intCast(i32, height));

        const cur_time = c.glfwGetTime();
        const dt = @floatCast(f32, cur_time - last_time);
        last_time = cur_time;

        const mouse_pos = try window.getMousePos();

        try ui.startBuild(width, height, mouse_pos, &window.event_queue);
        ui.endBuild(dt);

        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        try ui.render();

        window.update();
        frame_idx += 1;
        tracy.FrameMark();
    }
}

const MemoryStats = struct {
    virtual_size: usize,
    in_ram_size: usize,
    shared_size: usize,
};
pub fn getMemoryStats(allocator: Allocator) !MemoryStats {
    // note: we can use /proc/self/status for a more granular look at memory sizes
    const file = try std.fs.openFileAbsolute("/proc/self/statm", .{});
    defer file.close();
    const data = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(data);

    var tokenizer = std.mem.tokenize(u8, data, " ");
    var values: [3]u64 = undefined;
    for (values) |*value| {
        value.* = try std.fmt.parseInt(u64, tokenizer.next().?, 0);
    }

    // the values we just parsed are measured in pages, not bytes
    const page_size = @intCast(u64, c.sysconf(c._SC_PAGESIZE));

    return MemoryStats{
        .virtual_size = values[0] * page_size,
        .in_ram_size = values[1] * page_size,
        .shared_size = values[2] * page_size,
    };
}
