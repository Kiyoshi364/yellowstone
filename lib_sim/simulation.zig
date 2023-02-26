const std = @import("std");

pub const examples = @import("examples.zig");

pub const sandboxed = @import("models/sandboxed.zig");
pub const Sandboxed = sandboxed.Sandboxed;

pub const sandboxed_noalloc = @import("models/sandboxed_noalloc.zig");
pub const SandboxedNoAlloc = sandboxed_noalloc.SandboxedNoAlloc;

test "It compiles!" {
    std.testing.refAllDeclsRecursive(@This());
    std.testing.refAllDeclsRecursive(sandboxed);
    std.testing.refAllDeclsRecursive(sandboxed_noalloc);
}
