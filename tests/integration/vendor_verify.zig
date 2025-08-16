const std = @import("std");
const vendor = @import("vendor"); // <-- from build.zig

test "third_party checksums verify" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    try vendor.verifyAll(gpa.allocator()); // robust: no hardcoded paths
}
