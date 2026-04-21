const std = @import("std");
const lmdb = @cImport({
    @cInclude("lmdb.h");
});

pub const Database = struct {
    env: ?*lmdb.MDB_env,
    dbi: lmdb.MDB_dbi,
    txn: ?*lmdb.MDB_txn,

    /// Returns a dummy database instance with null handles.
    /// Useful for tests that mock data structs manually.
    pub const null_database = Database{
        .env = null,
        .dbi = 0,
        .txn = null,
    };

    pub fn init(path: []const u8) !Database {
        var env: ?*lmdb.MDB_env = null;
        try expectSuccess(lmdb.mdb_env_create(&env));
        errdefer lmdb.mdb_env_close(env);

        // LMDB map size (100MB)
        try expectSuccess(lmdb.mdb_env_set_mapsize(env, 100 * 1024 * 1024));
        
        // Open with MDB_RDONLY, MDB_NOSUBDIR (single file), and MDB_NOLOCK.
        // MDB_NOLOCK is safe for read-only access.
        const path_z = try std.heap.c_allocator.dupeZ(u8, path);
        defer std.heap.c_allocator.free(path_z);
        
        try expectSuccess(lmdb.mdb_env_open(env, path_z, lmdb.MDB_RDONLY | lmdb.MDB_NOSUBDIR | lmdb.MDB_NOLOCK, 0o664));

        var dbi: lmdb.MDB_dbi = 0;
        var txn: ?*lmdb.MDB_txn = null;
        
        // Start a long-lived read-only transaction
        try expectSuccess(lmdb.mdb_txn_begin(env, null, lmdb.MDB_RDONLY, &txn));
        errdefer lmdb.mdb_txn_abort(txn);

        // Open the default database
        try expectSuccess(lmdb.mdb_dbi_open(txn, null, 0, &dbi));

        return Database{
            .env = env,
            .dbi = dbi,
            .txn = txn,
        };
    }

    pub fn deinit(self: *Database) void {
        if (self.txn) |t| lmdb.mdb_txn_abort(t);
        if (self.env) |e| lmdb.mdb_env_close(e);
        self.txn = null;
        self.env = null;
    }

    pub fn get(self: *const Database, key: []const u8) ![]const u8 {
        // Pad key to 8-byte boundary to ensure value alignment
        var padded_key: [64]u8 = undefined;
        if (key.len > padded_key.len) return error.KeyTooLong;
        @memcpy(padded_key[0..key.len], key);
        
        const padding_needed = (8 - (key.len % 8)) % 8;
        const padded_len = key.len + padding_needed;
        if (padding_needed > 0) {
            @memset(padded_key[key.len..padded_len], 0);
        }
        
        var k = lmdb.MDB_val{ .mv_size = padded_len, .mv_data = &padded_key };
        var v = lmdb.MDB_val{ .mv_size = 0, .mv_data = null };

        const rc = lmdb.mdb_get(self.txn, self.dbi, &k, &v);
        if (rc == lmdb.MDB_NOTFOUND) return error.KeyNotFound;
        try expectSuccess(rc);

        return @as([*]const u8, @ptrCast(v.mv_data))[0..v.mv_size];
    }

    fn expectSuccess(rc: c_int) !void {
        if (rc != 0) {
            // Note: Consider logging or converting this to a Zig error
            // std.debug.print("LMDB Error: {s} ({d})\n", .{ lmdb.mdb_strerror(rc), rc });
            return error.LmdbError;
        }
    }
};
