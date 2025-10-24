const std = @import("std");

// ─────────────────────────────────────────────────────────────────────────────
// Limits & exported default
// ─────────────────────────────────────────────────────────────────────────────

/// Hard limits for HTTP parsing in the preview server.
pub const Limits = struct {
    /// Max bytes allowed for the request line (method SP target SP version CRLF).
    max_request_line: usize = 8 * 1024, // 8 KiB
    /// Max raw header bytes (from after request line through CRLF CRLF inclusive).
    max_headers_bytes: usize = 64 * 1024, // 64 KiB
    /// Max body size (when Content-Length is provided).
    max_body_bytes: usize = 4 * 1024 * 1024, // 4 MiB
};

/// Exported default limits (so callers don’t have to write `Limits{}`).
pub const DEFAULT: Limits = .{};

// ─────────────────────────────────────────────────────────────────────────────
// Error set & reader callback type
// ─────────────────────────────────────────────────────────────────────────────

pub const ReadError = error{
    RequestLineTooLong,
    HeadersTooLarge,
    Malformed,
    BodyTooLarge,
    EndOfStream,
};

/// Reader callback signature: returns number of bytes read or an error.
pub const ReadFn = fn (*anyopaque, []u8) anyerror!usize;

// ─────────────────────────────────────────────────────────────────────────────
// Request line
// ─────────────────────────────────────────────────────────────────────────────

/// Read the HTTP request line with a byte cap.
/// Returns the bytes of the request line **including** the trailing CRLF when possible.
pub fn readRequestLineWithLimit(
    ctx: *anyopaque,
    read_cb: ReadFn,
    allocator: std.mem.Allocator,
    lim: Limits,
) ReadError![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(allocator);

    var prev: u8 = 0;
    while (true) {
        var tmp: [512]u8 = undefined;
        const n = read_cb(ctx, tmp[0..]) catch |e| switch (e) {
            error.WouldBlock, error.Interrupted => continue,
            else => return ReadError.Malformed,
        };
        if (n == 0) return ReadError.EndOfStream;

        // Append; map OOM → Malformed to keep error set stable
        buf.appendSlice(allocator, tmp[0..n]) catch return ReadError.Malformed;
        if (buf.items.len > lim.max_request_line) return ReadError.RequestLineTooLong;

        // Scan for CRLF between the newly appended bytes and the trailing edge.
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const c = tmp[i];
            if (prev == '\r' and c == '\n') {
                // position right after LF in combined buffer
                const end = buf.items.len - (n - i - 1);
                return allocator.dupe(u8, buf.items[0..end]) catch return ReadError.Malformed;
            }
            prev = c;
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Headers
// ─────────────────────────────────────────────────────────────────────────────

/// Read raw header bytes until CRLF CRLF, enforcing max size.
/// Returns the full header block **including** the terminating CRLF CRLF.
pub fn readHeadersWithLimit(
    ctx: *anyopaque,
    read_cb: ReadFn,
    allocator: std.mem.Allocator,
    lim: Limits,
) ReadError![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .{};
    defer out.deinit(allocator);

    var last4: [4]u8 = .{ 0, 0, 0, 0 };

    while (true) {
        var tmp: [1024]u8 = undefined;
        const n = read_cb(ctx, tmp[0..]) catch |e| switch (e) {
            error.WouldBlock, error.Interrupted => continue,
            else => return ReadError.Malformed,
        };
        if (n == 0) return ReadError.Malformed;

        out.appendSlice(allocator, tmp[0..n]) catch return ReadError.Malformed;
        if (out.items.len > lim.max_headers_bytes) return ReadError.HeadersTooLarge;

        var i: usize = 0;
        while (i < n) : (i += 1) {
            const c = tmp[i];
            last4 = .{ last4[1], last4[2], last4[3], c };
            if (last4[0] == '\r' and last4[1] == '\n' and last4[2] == '\r' and last4[3] == '\n') {
                return allocator.dupe(u8, out.items) catch return ReadError.Malformed;
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Content-Length
// ─────────────────────────────────────────────────────────────────────────────

/// Parse Content-Length (case-insensitive) from a raw header block.
/// Returns 0 if the header is absent or unparsable.
pub fn contentLengthFrom(headers: []const u8) u64 {
    var it = std.mem.splitScalar(u8, headers, '\n');
    while (it.next()) |line_with_cr| {
        const line = if (line_with_cr.len > 0 and line_with_cr[line_with_cr.len - 1] == '\r')
            line_with_cr[0 .. line_with_cr.len - 1]
        else
            line_with_cr;
        if (std.ascii.startsWithIgnoreCase(line, "content-length:")) {
            // Skip colon and optional whitespace
            var p = line[15..];
            while (p.len > 0 and (p[0] == ' ' or p[0] == '\t')) p = p[1..];
            // Read number until whitespace or end
            var j: usize = 0;
            while (j < p.len and std.ascii.isDigit(p[j])) : (j += 1) {}
            if (j == 0) return 0;
            return std.fmt.parseInt(u64, p[0..j], 10) catch 0;
        }
    }
    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Body
// ─────────────────────────────────────────────────────────────────────────────

/// Read exactly `Content-Length` bytes, enforcing `lim.max_body_bytes`.
/// Returns `BodyTooLarge` if the announced size exceeds the limit, or `Malformed`
/// if allocation fails or fewer bytes are received than promised.
pub fn readBodyWithLimit(
    ctx: *anyopaque,
    read_cb: ReadFn,
    allocator: std.mem.Allocator,
    lim: Limits,
    content_len: u64,
) ReadError![]u8 {
    if (content_len > lim.max_body_bytes) return ReadError.BodyTooLarge;
    const want: usize = @intCast(content_len);

    var out = allocator.alloc(u8, want) catch return ReadError.Malformed;
    var filled: usize = 0;
    while (filled < want) {
        const n = read_cb(ctx, out[filled..want]) catch |e| switch (e) {
            error.WouldBlock, error.Interrupted => continue,
            else => {
                allocator.free(out);
                return ReadError.Malformed;
            },
        };
        if (n == 0) break;
        filled += n;
    }

    if (filled != want) {
        allocator.free(out);
        return ReadError.Malformed;
    }
    return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests (quick smoke checks)
// ─────────────────────────────────────────────────────────────────────────────

const MockReader = struct {
    data: []const u8,
    pos: usize = 0,
    fn read(self: *MockReader, buf: []u8) !usize {
        if (self.pos >= self.data.len) return @as(usize, 0);
        const n = @min(buf.len, self.data.len - self.pos);
        @memcpy(buf[0..n], self.data[self.pos .. self.pos + n]);
        self.pos += n;
        return n;
    }
};

fn mockReadCb(ctx: *anyopaque, buf: []u8) !usize {
    const self: *MockReader = @ptrCast(@alignCast(ctx));
    return self.read(buf);
}

test "contentLengthFrom basic" {
    const hdr =
        "Host: x\r\n" ++
        "Content-Length: 42\r\n" ++
        "\r\n";
    try std.testing.expectEqual(@as(u64, 42), contentLengthFrom(hdr));
}

test "readRequestLineWithLimit finds CRLF and caps size" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();

    var mr = MockReader{ .data = "GET /view?path=docs/SPEC.dcz HTTP/1.1\r\nHost: x\r\n\r\n" };
    const line = try readRequestLineWithLimit(&mr, mockReadCb, A, DEFAULT);
    defer A.free(line);
    try std.testing.expect(std.mem.endsWith(u8, line, "\r\n"));
    try std.testing.expect(std.mem.startsWith(u8, line, "GET "));
}

test "readHeadersWithLimit collects until CRLFCRLF and enforces cap" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();

    const headers_bytes =
        "Host: x\r\n" ++
        "Content-Type: text/plain\r\n" ++
        "\r\n";
    var mr = MockReader{ .data = headers_bytes };
    const headers = try readHeadersWithLimit(&mr, mockReadCb, A, DEFAULT);
    defer A.free(headers);
    try std.testing.expect(std.mem.endsWith(u8, headers, "\r\n\r\n"));

    const big = try A.alloc(u8, (64 * 1024) + 10);
    defer A.free(big);
    @memset(big, 'a');
    var mr2 = MockReader{ .data = big };
    try std.testing.expectError(ReadError.HeadersTooLarge, readHeadersWithLimit(&mr2, mockReadCb, A, DEFAULT));
}

test "readBodyWithLimit respects Content-Length and cap" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();

    const body = "hello-world";
    var mr = MockReader{ .data = body };
    const out = try readBodyWithLimit(&mr, mockReadCb, A, DEFAULT, body.len);
    defer A.free(out);
    try std.testing.expectEqualStrings(body, out);

    var mr2 = MockReader{ .data = body };
    try std.testing.expectError(ReadError.BodyTooLarge, readBodyWithLimit(&mr2, mockReadCb, A, Limits{ .max_body_bytes = 4 }, body.len));
}
