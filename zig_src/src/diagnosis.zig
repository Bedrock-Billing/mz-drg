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

    pub fn initWithData(data: []const u8) !DiagnosisData {
        const mapped = try common.MappedFile(DiagnosisHeader).initWithData(data, 0x44494147);
        return DiagnosisData{ .mapped = mapped };
    }

    pub fn deinit(self: *DiagnosisData) void {
        self.mapped.deinit();
    }

    pub fn getSchemes(self: *const DiagnosisData) ![]align(1) const MsdrgDiagnosis {
        return try self.mapped.getSlice(MsdrgDiagnosis, self.mapped.header.schemes_offset, self.mapped.header.num_schemes);
    }

    pub fn getEntries(self: *const DiagnosisData) ![]align(1) const DiagnosisEntry {
        return try self.mapped.getSlice(DiagnosisEntry, self.mapped.header.diagnoses_offset, self.mapped.header.num_diagnoses);
    }

    pub fn getDiagnoses(self: *const DiagnosisData) ![]align(1) const DiagnosisEntry {
        return try self.getEntries();
    }

    pub fn getDiagnosis(self: *const DiagnosisData, code: []const u8, version: i32) !?DiagnosisEntry {
        const diagnoses = try self.getDiagnoses();

        const Adapter = common.search.codeKey(DiagnosisEntry);
        return common.search.versionedBinarySearch(DiagnosisEntry, []const u8, Adapter.getKey, Adapter.compare, Adapter.equal, diagnoses, code, version);
    }
};

test "DiagnosisData lookup" {
    const filename = "test_diagnosis.bin";
    const file = try std.Io.Dir.createFile(std.Io.Dir.cwd(), std.testing.io, filename, .{ .read = true });
    defer {
        std.Io.File.close(file, std.testing.io);
        std.Io.Dir.deleteFile(std.Io.Dir.cwd(), std.testing.io, filename) catch {};
    }

    const writeU32 = struct {
        fn call(f: std.Io.File, v: u32) !void {
            var b: [4]u8 = undefined;
            std.mem.writeInt(u32, &b, v, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
        }
    }.call;

    const writeEntry = struct {
        fn call(f: std.Io.File, code: []const u8, v_start: i32, v_end: i32, scheme: i32) !void {
            var code_buf: [8]u8 = [_]u8{0} ** 8;
            @memcpy(code_buf[0..code.len], code);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &code_buf);

            var b: [4]u8 = undefined;
            std.mem.writeInt(i32, &b, v_start, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
            std.mem.writeInt(i32, &b, v_end, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
            std.mem.writeInt(i32, &b, scheme, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
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
    const d1 = try data.getDiagnosis("A001", 405);
    try std.testing.expect(d1 != null);
    try std.testing.expectEqual(@as(i32, 1), d1.?.scheme_id);

    const d2 = try data.getDiagnosis("A001", 420);
    try std.testing.expect(d2 != null);
    try std.testing.expectEqual(@as(i32, 2), d2.?.scheme_id);

    const d3 = try data.getDiagnosis("B002", 400);
    try std.testing.expect(d3 != null);
    try std.testing.expectEqual(@as(i32, 3), d3.?.scheme_id);

    const d4 = try data.getDiagnosis("C999", 400);
    try std.testing.expect(d4 == null);

    const d5 = try data.getDiagnosis("A001", 399); // Version mismatch
    try std.testing.expect(d5 == null);
}
