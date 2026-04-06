const std = @import("std");
const common = @import("common.zig");

/// Direction of code conversion.
pub const Direction = enum(u8) {
    FORWARD = 0, // newer → older
    BACKWARD = 1, // older → newer
};

/// Binary file header for ICD-10 conversion data.
const ConversionHeader = extern struct {
    magic: u32,
    num_pairs: u32,
    entries_offset: u32,
};

/// Entry size in bytes: 8 (source) + 8 (target) + 4 (date) + 2 (pair) + 1 (dir) = 23
const ENTRY_SIZE = 23;

/// Offsets within each entry
const OFF_SOURCE: usize = 0;
const OFF_TARGET: usize = 8;
const OFF_DATE: usize = 16;
const OFF_PAIR: usize = 20;
const OFF_DIR: usize = 22;

pub const ConversionData = struct {
    mapped: common.MappedFile(ConversionHeader),
    num_pairs: u32,
    entries_offset: u32,
    num_entries: u32,

    pub fn init(path: []const u8, magic: u32) !ConversionData {
        const mapped = try common.MappedFile(ConversionHeader).init(path, magic);
        const header = mapped.header;
        const num_pairs = header.num_pairs;
        const entries_offset = header.entries_offset;
        const file_size = mapped.map.memory.len;

        if (entries_offset > file_size) return error.InvalidData;
        const data_size = file_size - entries_offset;
        const num_entries: u32 = @intCast(data_size / ENTRY_SIZE);

        return ConversionData{
            .mapped = mapped,
            .num_pairs = num_pairs,
            .entries_offset = entries_offset,
            .num_entries = num_entries,
        };
    }

    pub fn deinit(self: *ConversionData) void {
        self.mapped.deinit();
    }

    /// Get raw bytes of entry at index.
    fn entryBytes(self: *const ConversionData, index: usize) [*]const u8 {
        return self.mapped.base_ptr() + self.entries_offset + (index * ENTRY_SIZE);
    }

    /// Read source code from entry (8 bytes).
    fn entrySource(self: *const ConversionData, index: usize) *const [8]u8 {
        return @ptrCast(entryBytes(self, index) + OFF_SOURCE);
    }

    /// Read target code from entry (8 bytes).
    fn entryTarget(self: *const ConversionData, index: usize) *const [8]u8 {
        return @ptrCast(entryBytes(self, index) + OFF_TARGET);
    }

    /// Read pair_index from entry (u16, unaligned).
    fn entryPairIndex(self: *const ConversionData, index: usize) u16 {
        const ptr = entryBytes(self, index) + OFF_PAIR;
        return std.mem.readInt(u16, ptr[0..2], .little);
    }

    /// Read direction from entry (u8).
    fn entryDirection(self: *const ConversionData, index: usize) u8 {
        return entryBytes(self, index)[OFF_DIR];
    }

    /// Get the pair index for a given source→target year conversion.
    fn getPairIndex(self: *const ConversionData, source_year: u32, target_year: u32) ?u16 {
        const years_ptr: [*]const u32 = @ptrCast(@alignCast(self.mapped.base_ptr() + 12));
        const min_year = if (source_year < target_year) source_year else target_year;

        var i: usize = 0;
        while (i < self.num_pairs) : (i += 1) {
            if (years_ptr[i] == min_year) {
                return @intCast(i);
            }
        }
        return null;
    }

    /// BACKWARD (older→newer) when source < target.
    /// FORWARD (newer→older) when source > target.
    fn getDirection(source_year: u32, target_year: u32) Direction {
        if (source_year < target_year) return .BACKWARD;
        return .FORWARD;
    }

    /// Binary search for first entry with pair_index >= target.
    fn findPairStart(self: *const ConversionData, target_pair: u16) usize {
        var lo: usize = 0;
        var hi: usize = self.num_entries;

        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.entryPairIndex(mid) < target_pair) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        return lo;
    }

    /// Binary search for first entry with pair_index > target.
    fn findPairEnd(self: *const ConversionData, target_pair: u16) usize {
        var lo: usize = 0;
        var hi: usize = self.num_entries;

        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.entryPairIndex(mid) <= target_pair) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        return lo;
    }

    fn codeLessThan(a: *const [8]u8, b: *const [8]u8) bool {
        return std.mem.order(u8, a, b) == .lt;
    }

    fn codeEqual(a: *const [8]u8, b: *const [8]u8) bool {
        return std.mem.eql(u8, a, b);
    }

    /// Look up a single code conversion.
    /// Returns the target code (8 bytes) if found, or null.
    pub fn lookup(
        self: *const ConversionData,
        source_code: *const [8]u8,
        source_year: u32,
        target_year: u32,
    ) ?[8]u8 {
        const pair_idx = self.getPairIndex(source_year, target_year) orelse return null;
        const dir = @intFromEnum(getDirection(source_year, target_year));

        const pair_start = self.findPairStart(pair_idx);
        const pair_end = self.findPairEnd(pair_idx);

        if (pair_start >= pair_end) return null;

        // Binary search within the pair's entries
        var lo = pair_start;
        var hi = pair_end;

        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            const src = self.entrySource(mid);

            if (codeLessThan(src, source_code)) {
                lo = mid + 1;
            } else if (codeLessThan(source_code, src)) {
                hi = mid;
            } else {
                // Found matching source code — scan for matching direction
                // First, backtrack to first entry with this source
                var best = mid;
                var scan = mid;
                while (scan > pair_start) : (scan -= 1) {
                    if (!codeEqual(self.entrySource(scan - 1), source_code)) break;
                    best = scan - 1;
                }
                // Scan forward from best to find matching direction
                scan = best;
                while (scan < pair_end) : (scan += 1) {
                    if (!codeEqual(self.entrySource(scan), source_code)) break;
                    if (self.entryDirection(scan) == dir) {
                        return self.entryTarget(scan).*;
                    }
                }
                return null;
            }
        }

        return null;
    }

    /// Convert a code string.
    /// Dots are stripped automatically (e.g., "B88.0" → "B880").
    /// Returns converted code as sentinel string, or null if no mapping.
    pub fn convertCode(
        self: *const ConversionData,
        code_str: []const u8,
        source_year: u32,
        target_year: u32,
        alloc: std.mem.Allocator,
    ) !?[:0]const u8 {
        // Pack code into 8-byte format, stripping dots and uppercasing
        var code: [8]u8 = [_]u8{0} ** 8;
        var pos: usize = 0;
        for (code_str) |c| {
            if (c == '.') continue;
            if (pos >= 8) break;
            code[pos] = std.ascii.toUpper(c);
            pos += 1;
        }

        if (self.lookup(&code, source_year, target_year)) |target| {
            var len: usize = 0;
            while (len < 8 and target[len] != 0) : (len += 1) {}
            const result = try alloc.allocSentinel(u8, len, 0);
            @memcpy(result, target[0..len]);
            return result;
        }
        return null;
    }
};

// --- Tests ---

test "ConversionHeader size" {
    try std.testing.expectEqual(@as(usize, 12), @sizeOf(ConversionHeader));
}

test "Direction enum" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(Direction.FORWARD));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(Direction.BACKWARD));
}
