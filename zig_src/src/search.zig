const std = @import("std");

/// Generic versioned binary search over a sorted, aligned-at-1 entry slice.
///
/// All binary data tables in this library share the same lookup pattern:
///   1. Binary search by a primary key (code string or integer)
///   2. On match, scan backward/forward to find the entry whose version range
///      contains the requested version.
///
/// This function extracts that pattern into a single generic implementation,
/// parameterized by the entry type and key extraction/comparison functions.
///
/// Parameters:
///   - `Entry`:     The extern struct type stored in the binary table (must be align(1)-safe).
///   - `KeyType`:   The type of the primary search key.
///   - `getKey`:    Extracts the comparable key from an entry (e.g., `entry.code.toSlice()`).
///   - `compareKeys`: Returns the ordering between two keys.
///   - `entries`:   The slice of entries to search.
///   - `key`:       The key to search for.
///   - `version`:   The version number to match within the entry's [version_start, version_end].
///
/// Returns the first matching entry, or null if no entry matches both key and version.
pub fn versionedBinarySearch(
    comptime Entry: type,
    comptime KeyType: type,
    comptime getKey: fn (entry: *align(1) const Entry) KeyType,
    comptime compareKeys: fn (a: KeyType, b: KeyType) std.math.Order,
    comptime keysEqual: fn (a: KeyType, b: KeyType) bool,
    entries: anytype,
    key: KeyType,
    version: i32,
) ?Entry {
    var left: usize = 0;
    var right: usize = entries.len;

    while (left < right) {
        const mid = left + (right - left) / 2;
        const entry_key = getKey(&entries[mid]);

        switch (compareKeys(entry_key, key)) {
            .lt => left = mid + 1,
            .gt => right = mid,
            .eq => {
                // Found a match — check version, then scan neighbors.
                if (version >= entries[mid].version_start and version <= entries[mid].version_end) {
                    return entries[mid];
                }

                // Scan backwards for same key with matching version
                var i = mid;
                while (i > 0) {
                    i -= 1;
                    if (!keysEqual(getKey(&entries[i]), key)) break;
                    if (version >= entries[i].version_start and version <= entries[i].version_end) return entries[i];
                }

                // Scan forwards
                i = mid + 1;
                while (i < entries.len) {
                    if (!keysEqual(getKey(&entries[i]), key)) break;
                    if (version >= entries[i].version_start and version <= entries[i].version_end) return entries[i];
                    i += 1;
                }

                return null; // Key found, but no matching version
            },
        }
    }
    return null;
}

// ============================================================================
// Convenience key adapters for the two common patterns
// ============================================================================

/// Key adapter for entries keyed by `common.Code` (8-byte null-padded string).
/// Use with entries that have a `.code` field of type `common.Code`.
pub fn codeKey(comptime Entry: type) type {
    return struct {
        pub fn getKey(entry: *align(1) const Entry) []const u8 {
            return entry.code.toSlice();
        }

        pub fn compare(a: []const u8, b: []const u8) std.math.Order {
            return std.mem.order(u8, a, b);
        }

        pub fn equal(a: []const u8, b: []const u8) bool {
            return std.mem.eql(u8, a, b);
        }
    };
}

/// Key adapter for entries keyed by a scalar integer field.
pub fn intKey(comptime Entry: type, comptime FieldType: type, comptime field_name: []const u8) type {
    return struct {
        pub fn getKey(entry: *align(1) const Entry) FieldType {
            return @field(entry, field_name);
        }

        pub fn compare(a: FieldType, b: FieldType) std.math.Order {
            return std.math.order(a, b);
        }

        pub fn equal(a: FieldType, b: FieldType) bool {
            return a == b;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

const TestEntry = extern struct {
    code: @import("common.zig").Code,
    version_start: i32,
    version_end: i32,
    value: i32,
};

const TestIntEntry = extern struct {
    id: u16,
    _pad: u16 = 0,
    version_start: i32,
    version_end: i32,
};

test "versionedBinarySearch with code key" {
    const Adapter = codeKey(TestEntry);
    const entries = [_]TestEntry{
        .{ .code = .{ .value = "A001\x00\x00\x00\x00".* }, .version_start = 400, .version_end = 410, .value = 1 },
        .{ .code = .{ .value = "A001\x00\x00\x00\x00".* }, .version_start = 411, .version_end = 431, .value = 2 },
        .{ .code = .{ .value = "B002\x00\x00\x00\x00".* }, .version_start = 400, .version_end = 431, .value = 3 },
    };

    // Match first version range
    const r1 = versionedBinarySearch(TestEntry, []const u8, Adapter.getKey, Adapter.compare, Adapter.equal, &entries, "A001", 405);
    try std.testing.expect(r1 != null);
    try std.testing.expectEqual(@as(i32, 1), r1.?.value);

    // Match second version range
    const r2 = versionedBinarySearch(TestEntry, []const u8, Adapter.getKey, Adapter.compare, Adapter.equal, &entries, "A001", 420);
    try std.testing.expect(r2 != null);
    try std.testing.expectEqual(@as(i32, 2), r2.?.value);

    // No matching version
    const r3 = versionedBinarySearch(TestEntry, []const u8, Adapter.getKey, Adapter.compare, Adapter.equal, &entries, "A001", 399);
    try std.testing.expect(r3 == null);

    // Code not found
    const r4 = versionedBinarySearch(TestEntry, []const u8, Adapter.getKey, Adapter.compare, Adapter.equal, &entries, "ZZZZ", 420);
    try std.testing.expect(r4 == null);

    // B002 match
    const r5 = versionedBinarySearch(TestEntry, []const u8, Adapter.getKey, Adapter.compare, Adapter.equal, &entries, "B002", 420);
    try std.testing.expect(r5 != null);
    try std.testing.expectEqual(@as(i32, 3), r5.?.value);
}

test "versionedBinarySearch with integer key" {
    const Adapter = intKey(TestIntEntry, u16, "id");
    const entries = [_]TestIntEntry{
        .{ .id = 5, .version_start = 400, .version_end = 431 },
        .{ .id = 10, .version_start = 400, .version_end = 410 },
        .{ .id = 10, .version_start = 411, .version_end = 431 },
        .{ .id = 20, .version_start = 400, .version_end = 431 },
    };

    const r1 = versionedBinarySearch(TestIntEntry, u16, Adapter.getKey, Adapter.compare, Adapter.equal, &entries, 10, 405);
    try std.testing.expect(r1 != null);
    try std.testing.expectEqual(@as(u16, 10), r1.?.id);

    const r2 = versionedBinarySearch(TestIntEntry, u16, Adapter.getKey, Adapter.compare, Adapter.equal, &entries, 10, 420);
    try std.testing.expect(r2 != null);

    const r3 = versionedBinarySearch(TestIntEntry, u16, Adapter.getKey, Adapter.compare, Adapter.equal, &entries, 99, 420);
    try std.testing.expect(r3 == null);
}
