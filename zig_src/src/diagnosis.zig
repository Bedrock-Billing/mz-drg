const std = @import("std");
const common = @import("common.zig");

pub const DiagnosisHeader = extern struct {
    magic: u32,
    num_schemes: u32,
    num_diagnoses: u32,
    schemes_offset: u32,
    diagnoses_offset: u32,
};

pub const MsdrgDiagnosis = extern struct {
    mdc: i32,
    severity: [4]u8,
    operands_pattern: i32,
    hac_operand_pattern: i32,
    dx_cat_list_pattern: i32,
};

pub const DiagnosisEntry = extern struct {
    code: common.Code,
    version_start: i32,
    version_end: i32,
    scheme_id: i32,
};

pub const DiagnosisData = struct {
    mapped: common.MappedFile(DiagnosisHeader),

    pub fn init(path: []const u8) !DiagnosisData {
        const mapped = try common.MappedFile(DiagnosisHeader).init(path, 0x44494147);
        return DiagnosisData{ .mapped = mapped };
    }

    pub fn deinit(self: *DiagnosisData) void {
        self.mapped.deinit();
    }

    pub fn getSchemes(self: *const DiagnosisData) []const MsdrgDiagnosis {
        const schemes_ptr = @as([*]const MsdrgDiagnosis, @ptrCast(@alignCast(self.mapped.base_ptr + self.mapped.header.schemes_offset)));
        return schemes_ptr[0..self.mapped.header.num_schemes];
    }

    pub fn getDiagnoses(self: *const DiagnosisData) []const DiagnosisEntry {
        const diagnoses_ptr = @as([*]const DiagnosisEntry, @ptrCast(@alignCast(self.mapped.base_ptr + self.mapped.header.diagnoses_offset)));
        return diagnoses_ptr[0..self.mapped.header.num_diagnoses];
    }

    pub fn getDiagnosis(self: *const DiagnosisData, code: []const u8, version: i32) ?DiagnosisEntry {
        const diagnoses = self.getDiagnoses();

        // Binary search for the code
        var left: usize = 0;
        var right: usize = diagnoses.len;

        while (left < right) {
            const mid = left + (right - left) / 2;
            const entry = diagnoses[mid];
            const entry_code = entry.code.toSlice();

            const order = std.mem.order(u8, entry_code, code);
            switch (order) {
                .lt => left = mid + 1,
                .gt => right = mid,
                .eq => {
                    // Found a match, but there might be multiple versions.
                    // We need to find the specific version.
                    // Since we sorted by key, version_start, we can scan around.
                    // But first, let's check if this one matches.
                    if (version >= entry.version_start and version <= entry.version_end) {
                        return entry;
                    }

                    // Scan backwards
                    var i = mid;
                    while (i > 0) {
                        i -= 1;
                        const prev = diagnoses[i];
                        if (!std.mem.eql(u8, prev.code.toSlice(), code)) break;
                        if (version >= prev.version_start and version <= prev.version_end) return prev;
                    }

                    // Scan forwards
                    i = mid + 1;
                    while (i < diagnoses.len) {
                        const next = diagnoses[i];
                        if (!std.mem.eql(u8, next.code.toSlice(), code)) break;
                        if (version >= next.version_start and version <= next.version_end) return next;
                        i += 1;
                    }

                    return null; // Code found, but version mismatch
                },
            }
        }
        return null;
    }
};

test "DiagnosisData lookup" {
    const filename = "test_diagnosis.bin";
    const file = try std.fs.cwd().createFile(filename, .{ .read = true });
    defer {
        file.close();
        std.fs.cwd().deleteFile(filename) catch {};
    }

    const writeU32 = struct {
        fn call(f: std.fs.File, v: u32) !void {
            var b: [4]u8 = undefined;
            std.mem.writeInt(u32, &b, v, .little);
            try f.writeAll(&b);
        }
    }.call;

    const writeEntry = struct {
        fn call(f: std.fs.File, code: []const u8, v_start: i32, v_end: i32, scheme: i32) !void {
            var code_buf: [8]u8 = [_]u8{0} ** 8;
            @memcpy(code_buf[0..code.len], code);
            try f.writeAll(&code_buf);

            var b: [4]u8 = undefined;
            std.mem.writeInt(i32, &b, v_start, .little);
            try f.writeAll(&b);
            std.mem.writeInt(i32, &b, v_end, .little);
            try f.writeAll(&b);
            std.mem.writeInt(i32, &b, scheme, .little);
            try f.writeAll(&b);
        }
    }.call;

    // Header: magic(4), num_schemes(4), num_diagnoses(4), schemes_offset(4), diagnoses_offset(4)
    try writeU32(file, 0x44494147);
    try writeU32(file, 0); // 0 schemes
    try writeU32(file, 3); // 3 diagnoses
    try writeU32(file, 20); // schemes offset (header size)
    try writeU32(file, 20); // diagnoses offset (no schemes)

    // Diagnoses (Sorted by code)
    // A001, v400-410
    try writeEntry(file, "A001", 400, 410, 1);
    // A001, v411-430
    try writeEntry(file, "A001", 411, 430, 2);
    // B002, v400-430
    try writeEntry(file, "B002", 400, 430, 3);

    var data = try DiagnosisData.init(filename);
    defer data.deinit();

    // Test lookup
    const d1 = data.getDiagnosis("A001", 405);
    try std.testing.expect(d1 != null);
    try std.testing.expectEqual(@as(i32, 1), d1.?.scheme_id);

    const d2 = data.getDiagnosis("A001", 420);
    try std.testing.expect(d2 != null);
    try std.testing.expectEqual(@as(i32, 2), d2.?.scheme_id);

    const d3 = data.getDiagnosis("B002", 400);
    try std.testing.expect(d3 != null);
    try std.testing.expectEqual(@as(i32, 3), d3.?.scheme_id);

    const d4 = data.getDiagnosis("C999", 400);
    try std.testing.expect(d4 == null);

    const d5 = data.getDiagnosis("A001", 399); // Version mismatch
    try std.testing.expect(d5 == null);
}
