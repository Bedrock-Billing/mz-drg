const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "msdrg",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);

    // Shared Library
    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "msdrg",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/c_api.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    lib.is_linking_libc = true;

    b.installArtifact(lib);

    // Auto-generate C header from exported functions
    const header_step = b.addWriteFiles();
    const header_file = header_step.add("msdrg.h", generateHeader(b));
    const install_header = b.addInstallFile(header_file, "include/msdrg.h");
    b.getInstallStep().dependOn(&install_header.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

fn generateHeader(b: *std.Build) []const u8 {
    _ = b;
    return
    \\#ifndef MSDRG_H
    \\#define MSDRG_H
    \\
    \\#include <stdbool.h>
    \\#include <stdint.h>
    \\
    \\#ifdef __cplusplus
    \\extern "C" {
    \\#endif
    \\
    \\/* Opaque handles */
    \\typedef void* MsdrgContext;
    \\typedef void* MsdrgVersion;
    \\typedef void* MsdrgInput;
    \\typedef void* MsdrgResult;
    \\
    \\/* ─── Context ─── */
    \\MsdrgContext msdrg_context_init(const char* data_dir);
    \\void msdrg_context_free(MsdrgContext ctx);
    \\
    \\/* ─── Version ─── */
    \\MsdrgVersion msdrg_version_create(MsdrgContext ctx, int32_t version);
    \\void msdrg_version_free(MsdrgVersion ver);
    \\
    \\/* ─── Input ─── */
    \\MsdrgInput msdrg_input_create(void);
    \\void msdrg_input_free(MsdrgInput input);
    \\bool msdrg_input_set_pdx(MsdrgInput input, const char* code, uint8_t poa);
    \\bool msdrg_input_set_admit_dx(MsdrgInput input, const char* code, uint8_t poa);
    \\bool msdrg_input_add_sdx(MsdrgInput input, const char* code, uint8_t poa);
    \\bool msdrg_input_add_procedure(MsdrgInput input, const char* code);
    \\void msdrg_input_set_demographics(MsdrgInput input, int32_t age, int32_t sex, int32_t discharge_status);
    \\void msdrg_input_set_hospital_status(MsdrgInput input, int32_t status);
    \\
    \\/* ─── Grouping (structured) ─── */
    \\MsdrgResult msdrg_group(MsdrgVersion ver, MsdrgInput input);
    \\void msdrg_result_free(MsdrgResult res);
    \\
    \\/* ─── Result: scalar getters ─── */
    \\int32_t msdrg_result_get_initial_drg(MsdrgResult res);
    \\int32_t msdrg_result_get_final_drg(MsdrgResult res);
    \\int32_t msdrg_result_get_initial_mdc(MsdrgResult res);
    \\int32_t msdrg_result_get_final_mdc(MsdrgResult res);
    \\int32_t msdrg_result_get_return_code(MsdrgResult res);
    \\const char* msdrg_result_get_return_code_name(MsdrgResult res);
    \\const char* msdrg_result_get_initial_drg_description(MsdrgResult res);
    \\const char* msdrg_result_get_final_drg_description(MsdrgResult res);
    \\const char* msdrg_result_get_initial_mdc_description(MsdrgResult res);
    \\const char* msdrg_result_get_final_mdc_description(MsdrgResult res);
    \\
    \\/* ─── Result: PDX output ─── */
    \\bool msdrg_result_has_pdx(MsdrgResult res);
    \\const char* msdrg_result_get_pdx_code(MsdrgResult res);
    \\int32_t msdrg_result_get_pdx_mdc(MsdrgResult res);
    \\const char* msdrg_result_get_pdx_severity(MsdrgResult res);
    \\const char* msdrg_result_get_pdx_drg_impact(MsdrgResult res);
    \\const char* msdrg_result_get_pdx_poa_error(MsdrgResult res);
    \\const char* msdrg_result_get_pdx_flags(MsdrgResult res);
    \\
    \\/* ─── Result: SDX output ─── */
    \\int32_t msdrg_result_get_sdx_count(MsdrgResult res);
    \\const char* msdrg_result_get_sdx_code(MsdrgResult res, int32_t index);
    \\int32_t msdrg_result_get_sdx_mdc(MsdrgResult res, int32_t index);
    \\const char* msdrg_result_get_sdx_severity(MsdrgResult res, int32_t index);
    \\const char* msdrg_result_get_sdx_drg_impact(MsdrgResult res, int32_t index);
    \\const char* msdrg_result_get_sdx_poa_error(MsdrgResult res, int32_t index);
    \\const char* msdrg_result_get_sdx_flags(MsdrgResult res, int32_t index);
    \\
    \\/* ─── Result: Procedure output ─── */
    \\int32_t msdrg_result_get_proc_count(MsdrgResult res);
    \\const char* msdrg_result_get_proc_code(MsdrgResult res, int32_t index);
    \\bool msdrg_result_get_proc_is_or(MsdrgResult res, int32_t index);
    \\const char* msdrg_result_get_proc_drg_impact(MsdrgResult res, int32_t index);
    \\bool msdrg_result_get_proc_is_valid(MsdrgResult res, int32_t index);
    \\const char* msdrg_result_get_proc_flags(MsdrgResult res, int32_t index);
    \\
    \\/* ─── JSON API ─── */
    \\const char* msdrg_group_json(MsdrgContext ctx, const char* json_str);
    \\const char* msdrg_result_to_json(MsdrgResult res);
    \\void msdrg_string_free(const char* s);
    \\
    \\/* ─── MCE Editor ─── */
    \\typedef void* MceContext;
    \\
    \\MceContext mce_context_init(const char* data_dir);
    \\void mce_context_free(MceContext ctx);
    \\const char* mce_edit_json(MceContext ctx, const char* json_str);
    \\
    \\#ifdef __cplusplus
    \\}
    \\#endif
    \\
    \\#endif /* MSDRG_H */
    ;
}
