const std = @import("std");
const common = @import("common.zig");

pub const FormulasHeader = extern struct {
    magic: u32,
    num_entries: u32,
    num_formulas: u32,
    entries_offset: u32,
    formulas_offset: u32,
    strings_offset: u32,
};

pub const FormulaEntryIndex = extern struct {
    mdc: i32,
    version_start: i32,
    version_end: i32,
    start_index: u32,
    count: u32,
};

pub const DrgFormula = extern struct {
    mdc: i32,
    rank: i32,
    base_drg: i32,
    drg: i32,
    surgical: [8]u8,
    reroute_mdc_id: i32,
    drg_severity: i32,
    formula_offset: u32,
    formula_len: u32,
    supp_offset: u32,
    supp_count: u32,

    pub fn getFormula(self: *const DrgFormula, base: [*]const u8) []const u8 {
        return base[self.formula_offset .. self.formula_offset + self.formula_len];
    }

    pub fn getSurgical(self: *const DrgFormula) []const u8 {
        var len: usize = 0;
        while (len < 8 and self.surgical[len] != 0) : (len += 1) {}
        return self.surgical[0..len];
    }
};

pub const FormulaData = struct {
    mapped: common.MappedFile(FormulasHeader),

    pub fn init(path: []const u8) !FormulaData {
        const mapped = try common.MappedFile(FormulasHeader).init(path, 0x464F524D);
        return FormulaData{ .mapped = mapped };
    }

    pub fn deinit(self: *FormulaData) void {
        self.mapped.deinit();
    }

    pub fn getEntries(self: *const FormulaData) []const FormulaEntryIndex {
        const entries_ptr = @as([*]const FormulaEntryIndex, @ptrCast(@alignCast(self.mapped.base_ptr + self.mapped.header.entries_offset)));
        return entries_ptr[0..self.mapped.header.num_entries];
    }

    pub fn getEntry(self: *const FormulaData, mdc: i32, version: i32) ?FormulaEntryIndex {
        const entries = self.getEntries();
        var left: usize = 0;
        var right: usize = entries.len;

        while (left < right) {
            const mid = left + (right - left) / 2;
            const entry = entries[mid];

            if (entry.mdc < mdc) {
                left = mid + 1;
            } else if (entry.mdc > mdc) {
                right = mid;
            } else {
                // Found match, check version
                if (version >= entry.version_start and version <= entry.version_end) {
                    return entry;
                }
                // Scan backwards
                var i = mid;
                while (i > 0) {
                    i -= 1;
                    const prev = entries[i];
                    if (prev.mdc != mdc) break;
                    if (version >= prev.version_start and version <= prev.version_end) return prev;
                }
                // Scan forwards
                i = mid + 1;
                while (i < entries.len) {
                    const next = entries[i];
                    if (next.mdc != mdc) break;
                    if (version >= next.version_start and version <= next.version_end) return next;
                    i += 1;
                }
                return null;
            }
        }
        return null;
    }

    pub fn getFormulas(self: *const FormulaData) []const DrgFormula {
        const formulas_ptr = @as([*]const DrgFormula, @ptrCast(@alignCast(self.mapped.base_ptr + self.mapped.header.formulas_offset)));
        return formulas_ptr[0..self.mapped.header.num_formulas];
    }

    pub fn getSuppressionList(self: *const FormulaData, offset: u32, count: u32) []const common.StringRef {
        const supp_ptr = @as([*]const common.StringRef, @ptrCast(@alignCast(self.mapped.base_ptr + offset)));
        return supp_ptr[0..count];
    }
};

test "FormulaData lookup" {
    const filename = "test_formula.bin";
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

    const writeI32 = struct {
        fn call(f: std.Io.File, v: i32) !void {
            var b: [4]u8 = undefined;
            std.mem.writeInt(i32, &b, v, .little);
            try std.Io.File.writeStreamingAll(f, std.testing.io, &b);
        }
    }.call;

    // Header: magic(4), num_entries(4), num_formulas(4), entries_off(4), formulas_off(4), strings_off(4)
    try writeU32(file, 0x464F524D);
    try writeU32(file, 2);
    try writeU32(file, 0); // 0 formulas for this test
    try writeU32(file, 24);
    try writeU32(file, 24 + 2 * 20); // 2 entries * 20 bytes
    try writeU32(file, 24 + 2 * 20); // no formulas

    // Entry 1: MDC 1, v400-410
    try writeI32(file, 1);
    try writeI32(file, 400);
    try writeI32(file, 410);
    try writeU32(file, 0); // start_index
    try writeU32(file, 0); // count

    // Entry 2: MDC 2, v400-430
    try writeI32(file, 2);
    try writeI32(file, 400);
    try writeI32(file, 430);
    try writeU32(file, 0); // start_index
    try writeU32(file, 0); // count

    var data = try FormulaData.init(filename);
    defer data.deinit();

    const e1 = data.getEntry(1, 405);
    try std.testing.expect(e1 != null);
    try std.testing.expectEqual(@as(i32, 1), e1.?.mdc);

    const e2 = data.getEntry(2, 420);
    try std.testing.expect(e2 != null);
    try std.testing.expectEqual(@as(i32, 2), e2.?.mdc);

    const e3 = data.getEntry(1, 420); // Version mismatch
    try std.testing.expect(e3 == null);
}

// --- Formula Parser & Evaluator ---

pub const TokenType = enum {
    ATOM,
    LPAREN,
    RPAREN,
    AND,
    OR,
    NOT,
};

pub const Token = struct {
    type: TokenType,
    value: []const u8,
    prefix: ?[]const u8 = null,
};

pub const Lexer = struct {
    input: []const u8,
    pos: usize,

    pub fn init(input: []const u8) Lexer {
        return Lexer{
            .input = input,
            .pos = 0,
        };
    }

    pub fn tokenize(self: *Lexer, allocator: std.mem.Allocator) !std.ArrayList(Token) {
        var tokens = try std.ArrayList(Token).initCapacity(allocator, 0);
        errdefer tokens.deinit(allocator);

        while (self.pos < self.input.len) {
            const c = self.input[self.pos];

            switch (c) {
                ' ', '\t', '\n', '\r' => {
                    self.pos += 1;
                },
                '(' => {
                    try tokens.append(allocator, Token{ .type = .LPAREN, .value = "(" });
                    self.pos += 1;
                },
                ')' => {
                    try tokens.append(allocator, Token{ .type = .RPAREN, .value = ")" });
                    self.pos += 1;
                },
                '&' => {
                    try tokens.append(allocator, Token{ .type = .AND, .value = "&" });
                    self.pos += 1;
                },
                '|' => {
                    try tokens.append(allocator, Token{ .type = .OR, .value = "|" });
                    self.pos += 1;
                },
                '~' => {
                    try tokens.append(allocator, Token{ .type = .NOT, .value = "~" });
                    self.pos += 1;
                },
                else => {
                    // Atom
                    const start = self.pos;
                    while (self.pos < self.input.len) {
                        const next_c = self.input[self.pos];
                        if (next_c == ' ' or next_c == '\t' or next_c == '\n' or next_c == '\r' or
                            next_c == '(' or next_c == ')' or next_c == '&' or next_c == '|' or next_c == '~')
                        {
                            break;
                        }
                        self.pos += 1;
                    }
                    const atom_text = self.input[start..self.pos];

                    // Parse prefix
                    var prefix: ?[]const u8 = null;
                    var value: []const u8 = atom_text;

                    if (std.mem.indexOf(u8, atom_text, ":")) |idx| {
                        prefix = atom_text[0..idx];
                        value = atom_text[idx + 1 ..];
                    }

                    try tokens.append(allocator, Token{
                        .type = .ATOM,
                        .value = value,
                        .prefix = prefix,
                    });
                },
            }
        }

        return tokens;
    }
};

pub const AstNode = union(enum) {
    And: struct { left: *AstNode, right: *AstNode },
    Or: struct { left: *AstNode, right: *AstNode },
    Not: struct { child: *AstNode },
    Contains: struct { prefix: ?[]const u8, value: []const u8 },
};

pub const Parser = struct {
    tokens: []const Token,
    pos: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, tokens: []const Token) Parser {
        return Parser{
            .tokens = tokens,
            .pos = 0,
            .allocator = allocator,
        };
    }

    pub fn parse(self: *Parser) !*AstNode {
        if (self.tokens.len == 0) return error.EmptyExpression;
        return self.parseExpression();
    }

    fn parseExpression(self: *Parser) !*AstNode {
        var left = try self.parseTerm();

        while (self.pos < self.tokens.len and self.tokens[self.pos].type == .OR) {
            self.pos += 1; // Eat OR
            const right = try self.parseTerm();

            const node = try self.allocator.create(AstNode);
            node.* = AstNode{ .Or = .{ .left = left, .right = right } };
            left = node;
        }
        return left;
    }

    fn parseTerm(self: *Parser) !*AstNode {
        var left = try self.parseFactor();

        while (self.pos < self.tokens.len and self.tokens[self.pos].type == .AND) {
            self.pos += 1; // Eat AND
            const right = try self.parseFactor();

            const node = try self.allocator.create(AstNode);
            node.* = AstNode{ .And = .{ .left = left, .right = right } };
            left = node;
        }
        return left;
    }

    fn parseFactor(self: *Parser) anyerror!*AstNode {
        if (self.pos >= self.tokens.len) return error.UnexpectedEndOfExpression;

        const token = self.tokens[self.pos];
        self.pos += 1;

        switch (token.type) {
            .ATOM => {
                const node = try self.allocator.create(AstNode);
                node.* = AstNode{ .Contains = .{ .prefix = token.prefix, .value = token.value } };
                return node;
            },
            .LPAREN => {
                const expr = try self.parseExpression();
                if (self.pos >= self.tokens.len or self.tokens[self.pos].type != .RPAREN) {
                    return error.MissingClosingParenthesis;
                }
                self.pos += 1; // Eat RPAREN
                return expr;
            },
            .NOT => {
                const factor = try self.parseFactor();
                const node = try self.allocator.create(AstNode);
                node.* = AstNode{ .Not = .{ .child = factor } };
                return node;
            },
            else => return error.UnexpectedToken,
        }
    }
};

pub const Evaluator = struct {
    pub fn evaluate(node: *AstNode, mask: *const std.StringHashMap(u32), mdc: i32) bool {
        switch (node.*) {
            .And => |n| return evaluate(n.left, mask, mdc) and evaluate(n.right, mask, mdc),
            .Or => |n| return evaluate(n.left, mask, mdc) or evaluate(n.right, mask, mdc),
            .Not => |n| return !evaluate(n.child, mask, mdc),
            .Contains => |n| {
                var buf: [128]u8 = undefined;
                var key: []const u8 = undefined;
                if (n.prefix) |p| {
                    const len = p.len + 1 + n.value.len;
                    if (len <= buf.len) {
                        @memcpy(buf[0..p.len], p);
                        buf[p.len] = ':';
                        @memcpy(buf[p.len + 1 ..][0..n.value.len], n.value);
                        key = buf[0..len];
                    } else {
                        return false;
                    }
                } else {
                    key = n.value;
                }

                if (mask.get(key)) |supp_mask| {
                    // Check suppression
                    // Java uses BitSet(32). If mdc is 0, 1<<0 = 1.
                    // Assuming mdc is 0-based index.
                    if (mdc >= 0 and mdc < 32) {
                        const mdc_bit = @as(u32, 1) << @as(u5, @intCast(mdc));
                        if ((supp_mask & mdc_bit) != 0) {
                            return false; // Suppressed
                        }
                    }
                    return true;
                }
                return false;
            },
        }
    }

    pub fn free(node: *AstNode, allocator: std.mem.Allocator) void {
        switch (node.*) {
            .And => |n| {
                free(n.left, allocator);
                free(n.right, allocator);
            },
            .Or => |n| {
                free(n.left, allocator);
                free(n.right, allocator);
            },
            .Not => |n| {
                free(n.child, allocator);
            },
            .Contains => {},
        }
        allocator.destroy(node);
    }

    pub fn collectMatchedAttributes(node: *AstNode, mask: *const std.StringHashMap(u32), matched: *std.StringHashMap(void), allocator: std.mem.Allocator, mdc: i32) !bool {
        if (!evaluate(node, mask, mdc)) return false;

        switch (node.*) {
            .And => |n| {
                _ = try collectMatchedAttributes(n.left, mask, matched, allocator, mdc);
                _ = try collectMatchedAttributes(n.right, mask, matched, allocator, mdc);
                return true;
            },
            .Or => |n| {
                if (evaluate(n.left, mask, mdc)) {
                    _ = try collectMatchedAttributes(n.left, mask, matched, allocator, mdc);
                }
                if (evaluate(n.right, mask, mdc)) {
                    _ = try collectMatchedAttributes(n.right, mask, matched, allocator, mdc);
                }
                return true;
            },
            .Not => {
                return true;
            },
            .Contains => |n| {
                var buf: [128]u8 = undefined;
                var key: []const u8 = undefined;
                if (n.prefix) |p| {
                    const len = p.len + 1 + n.value.len;
                    if (len <= buf.len) {
                        @memcpy(buf[0..p.len], p);
                        buf[p.len] = ':';
                        @memcpy(buf[p.len + 1 ..][0..n.value.len], n.value);
                        key = buf[0..len];
                    } else {
                        return false;
                    }
                } else {
                    key = n.value;
                }

                if (mask.get(key)) |supp_mask| {
                    if (mdc >= 0 and mdc < 32) {
                        const mdc_bit = @as(u32, 1) << @as(u5, @intCast(mdc));
                        if ((supp_mask & mdc_bit) != 0) {
                            return false; // Suppressed
                        }
                    }
                    const key_dupe = try allocator.dupe(u8, key);
                    try matched.put(key_dupe, {});
                    return true;
                }
                return false;
            },
        }
    }
};

test "formula parser and evaluator" {
    const allocator = std.testing.allocator;

    const input = "MCC & (AGE>65 | PDX:A001) & ~DIED";
    var lexer = Lexer.init(input);
    var tokens = try lexer.tokenize(allocator);
    defer tokens.deinit(allocator);

    var parser = Parser.init(allocator, tokens.items);
    const root = try parser.parse();
    defer Evaluator.free(root, allocator);

    var mask = std.StringHashMap(u32).init(allocator);
    defer mask.deinit();

    // Case 1: MCC present, AGE>65 present -> True
    try mask.put("MCC", 0);
    try mask.put("AGE>65", 0);
    try std.testing.expect(Evaluator.evaluate(root, &mask, 0));

    // Case 2: MCC present, PDX:A001 present -> True
    mask.clearRetainingCapacity();
    try mask.put("MCC", 0);
    try mask.put("PDX:A001", 0);
    try std.testing.expect(Evaluator.evaluate(root, &mask, 0));

    // Case 3: MCC missing -> False
    mask.clearRetainingCapacity();
    try mask.put("AGE>65", 0);
    try std.testing.expect(!Evaluator.evaluate(root, &mask, 0));

    // Case 4: DIED present -> False (because of ~DIED)
    mask.clearRetainingCapacity();
    try mask.put("MCC", 0);
    try mask.put("AGE>65", 0);
    try mask.put("DIED", 0);
    try std.testing.expect(!Evaluator.evaluate(root, &mask, 0));
}
