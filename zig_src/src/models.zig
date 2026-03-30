const std = @import("std");
const common = @import("common.zig");
const formula = @import("formula.zig");

pub const GrouperError = error{
    DX_CANNOT_BE_PDX,
};

pub const Sex = enum {
    MALE,
    FEMALE,
    UNKNOWN,
};

pub const DischargeStatus = enum(i32) {
    NONE = -1,
    HOME_SELFCARE_ROUTINE = 1,
    SHORT_TERM_HOSPITAL = 2,
    SNF = 3,
    CUST_SUPP_CARE = 4,
    CANC_CHILD_HOSP = 5,
    HOME_HEALTH_SERVICE = 6,
    LEFT_AGAINST_MEDICAL_ADVICE = 7,
    DIED = 20,
    COURT_LAW_ENFRC = 21,
    STILL_A_PATIENT = 30,
    FEDERAL_HOSPITAL = 43,
    HOSPICE_HOME = 50,
    HOSPICE_MEDICAL_FACILITY = 51,
    SWING_BED = 61,
    REHAB_FACILITY_REHAB_UNIT = 62,
    LONG_TERM_CARE_HOSPITAL = 63,
    NURSING_FACILITY_MEDICAID_CERTIFIED = 64,
    PSYCH_HOSP_UNIT = 65,
    CRIT_ACC_HOSP = 66,
    DESIGNATED_DISASTER_ALTERNATIVE_CARE_SITE = 69,
    OTH_INSTITUTION = 70,
    HOME_SELF_CARE_W_PLANNED_READMISSION = 81,
    SHORT_TERM_HOSPITAL_W_PLANNED_READMISSION = 82,
    SNF_W_PLANNED_READMISSION = 83,
    CUST_SUPP_CARE_W_PLANNED_READMISSION = 84,
    CANC_CHILD_HOSP_W_PLANNED_READMISSION = 85,
    HOME_HEALTH_SERVICE_W_PLANNED_READMISSION = 86,
    COURT_LAW_ENFRC_W_PLANNED_READMISSION = 87,
    FEDERAL_HOSPITAL_W_PLANNED_READMISSION = 88,
    SWING_BED_W_PLANNED_READMISSION = 89,
    REHAB_FACILITY_UNIT_W_PLANNED_READMISSION = 90,
    LTCH_W_PLANNED_READMISSION = 91,
    NURSG_FAC_MEDICAID_CERT_W_PLANNED_READMISSION = 92,
    PSYCH_HOSP_UNIT_W_PLANNED_READMISSION = 93,
    CRIT_ACC_HOSP_W_PLANNED_READMISSION = 94,
    OTH_INSTITUTION_W_PLANNED_READMISSION = 95,

    pub fn formulaString(self: DischargeStatus) ?[]const u8 {
        return switch (self) {
            .NONE => "invalid_dstat",
            .LEFT_AGAINST_MEDICAL_ADVICE => "AMA",
            .DIED => "DIED",
            else => null,
        };
    }
};

pub const Severity = enum {
    NONE,
    CC,
    MCC,
};

pub const GroupingImpact = enum(u8) {
    NONE = 0,
    INITIAL = 1,
    FINAL = 2,
    BOTH = 3,
};

pub const CodeSeverityFlag = enum(u8) {
    NEITHER = 0,
    MCC = 1,
    MCC_EXCLUDED_BY_DRG_LOGIC = 2,
    CC_EXCLUDED_BY_DRG_LOGIC = 3,
    CC = 5,
    MCC_EXCLUDED = 6,
    CC_EXCLUDED = 7,
};

pub const PoaErrorCode = enum(i8) {
    BLANK_DX_NOT_CONSIDERED = -1,
    POA_NOT_CHECKED = 0,
    POA_NOT_RECOGNIZED = 1,
    POA_RECOGNIZED_NOT_POA = 3,
    POA_RECOGNIZED_YES_POA = 4,
    HOSPITAL_EXEMPT = 5,
};

pub const HacUsage = enum(u8) {
    NOT_ON_HAC_LIST = 0,
    HAC_CRITERIA_MET = 1,
    HAC_CRITERIA_NOT_MET = 2,
    HAC_NOT_APPLICABLE_EXCLUSION = 3,
    HAC_NOT_APPLICABLE_EXEMPT = 4,
};

pub const ProcedureHacUsage = enum(i8) {
    BLANK = -1,
    HAC_NOT_USED = 0,
    HAC_08 = 1,
    HAC_10 = 2,
    HAC_11 = 3,
    HAC_12 = 4,
    HAC_13 = 5,
    HAC_14 = 6,
};

pub const Hac = struct {
    hac_status: HacUsage,
    hac_list: []const u8,
    hac_number: i32,
    description: []const u8,
};

pub const HospitalStatusOptionFlag = enum {
    EXEMPT,
    NOT_EXEMPT,
    UNKNOWN,
};

pub const MarkingLogicTieBreaker = enum {
    CLINICAL_SIGNIFICANCE,
    ALPHABETICAL,
};

pub const RuntimeOptions = struct {
    poa_reporting_exempt: HospitalStatusOptionFlag = .NOT_EXEMPT,
    tie_breaker: MarkingLogicTieBreaker = .CLINICAL_SIGNIFICANCE,
};

pub const GrouperReturnCode = enum {
    OK,
    INVALID_PRINCIPAL_DIAGNOSIS,
    INVALID_AGE,
    INVALID_SEX,
    INVALID_DISCHARGE_STATUS,
    DX_CANNOT_BE_PDX,
    UNGROUPABLE,
    INVALID_PDX,
    HAC_MISSING_ONE_POA,
    HAC_STATUS_INVALID_MULT_HACS_POA_NOT_Y_W,
    HAC_STATUS_INVALID_POA_N_OR_U,
    HAC_STATUS_INVALID_POA_INVALID_OR_1,
};

pub const CodeFlag = enum {
    AFFECTS_DRG,
    EXCLUDED,
    VALID,
    LIMITED_SEVERITY_TRAUMA,
    LIMITED_SEVERITY_HIV,
    SEX_CONFLICT,
    DOWNGRADE_SEVERITY_SUPPRESSION,
    MARKED_FOR_INITIAL,
    MARKED_FOR_FINAL,
    SIG_TRAUMA,
    ON_SHOW_LIST,
    DEATH_EXCLUSION,
    CLUSTER,
    BILATERAL,
    VESSEL_4,
    STENT_4,
    FIRST_POSITION,
    NOT_INCIDENT,
};

pub const AttributePrefix = enum {
    NONE,
    PDX,
    ONLY,
};

pub const SourceLogicLists = struct {
    pub const INVALID_PDX = "INVALID_PDX";
    pub const PDX_ECODE = "PDX_ECODE";
    pub const INVALID_SEX = "INVALID_SEX";
    pub const ANYDX = "ANYDX";
    pub const MULTST = "MULTST";
    pub const MDC_20_FALL_THRU = "MDC_20_FALL_THRU";
    pub const BILATERAL = "BILATERAL";
    pub const NORDRUGSTENT = "NORdrugstent";
    pub const NORSTENT = "NORstent";
    pub const FOUR_NON_DRUG_ELUTING_STENTS = "FOUR_NON_DRUG_ELUTING_STENTS";
    pub const FOUR_DRUG_ELUTING_STENTS = "FOUR_DRUG_ELUTING_STENTS";
    pub const FOUR_VESSELS = "FOUR_VESSELS";
    pub const FOUR_STENTS = "FOUR_STENTS";
    pub const MULTFUSE = "MULTFUSE";
    pub const SGLANTSECTXCTR = "SGLANTSECTXCTR";
    pub const SGLPOSTFUSECTR = "SGLPOSTFUSECTR";
    pub const SINGLEFUSIONCTR = "SINGLEFUSIONCTR";
    pub const SGLANTFUSECTR = "SGLANTCTR";
    pub const SGLPOST1FUSECTR = "SGLPOST1CTR";
};

pub const Attribute = struct {
    list_name: []const u8,
    prefix: AttributePrefix = .NONE,
    mdc_suppression: std.bit_set.IntegerBitSet(32) = std.bit_set.IntegerBitSet(32).initEmpty(),
    // Add other fields if needed (e.g., prefix, is_negative)

    pub fn eql(self: Attribute, other: Attribute) bool {
        return std.mem.eql(u8, self.list_name, other.list_name) and self.prefix == other.prefix;
    }

    pub fn toString(self: Attribute, allocator: std.mem.Allocator) ![]u8 {
        if (self.prefix == .NONE) {
            return allocator.dupe(u8, self.list_name);
        }
        const prefix_str = switch (self.prefix) {
            .PDX => "PDX",
            .ONLY => "ONLY",
            .NONE => "",
        };
        return std.fmt.allocPrint(allocator, "{s}:{s}", .{ prefix_str, self.list_name });
    }
};

pub const DiagnosisCode = struct {
    value: common.Code,
    poa: u8, // 'Y', 'N', 'U', 'W', '1'
    attributes: std.ArrayList(Attribute) = .empty,
    dx_cat_attributes: std.ArrayList(Attribute) = .empty,
    hac_attributes: std.ArrayList(Attribute) = .empty,
    flags: std.EnumSet(CodeFlag),
    mdc: ?i32,
    severity: Severity,
    hacs: std.ArrayList(Hac) = .empty,
    hacs_flags: std.ArrayList(Hac) = .empty,
    drg_impact: GroupingImpact,
    initial_severity_flag: CodeSeverityFlag,
    final_severity_flag: CodeSeverityFlag,
    clinical_significance_rank: ?i32,
    poa_error_code_flag: PoaErrorCode,
    attribute_marked_for: ?Attribute,

    pub fn init(code_str: []const u8, poa: u8) !DiagnosisCode {
        var code = common.Code{ .value = [_]u8{0} ** 8 };
        const len = @min(code_str.len, 8);
        @memcpy(code.value[0..len], code_str[0..len]);

        return DiagnosisCode{
            .value = code,
            .poa = poa,
            .flags = std.EnumSet(CodeFlag).initEmpty(),
            .mdc = null,
            .severity = .NONE,
            .drg_impact = .NONE,
            .initial_severity_flag = .NEITHER,
            .final_severity_flag = .NEITHER,
            .clinical_significance_rank = null,
            .poa_error_code_flag = .POA_NOT_CHECKED,
            .attribute_marked_for = null,
        };
    }

    pub fn deinit(self: *DiagnosisCode, allocator: std.mem.Allocator) void {
        self.attributes.deinit(allocator);
        self.dx_cat_attributes.deinit(allocator);
        self.hac_attributes.deinit(allocator);
        self.hacs.deinit(allocator);
        self.hacs_flags.deinit(allocator);
    }

    pub fn is(self: DiagnosisCode, flag: CodeFlag) bool {
        return self.flags.contains(flag);
    }

    pub fn mark(self: *DiagnosisCode, flag: CodeFlag) void {
        self.flags.insert(flag);
    }

    pub fn unMark(self: *DiagnosisCode, flag: CodeFlag) void {
        self.flags.remove(flag);
    }

    pub fn markSeverityFlag(self: *DiagnosisCode, impact: GroupingImpact) void {
        const flag: CodeSeverityFlag = switch (self.severity) {
            .MCC => .MCC,
            .CC => .CC,
            .NONE => .NEITHER,
        };

        if (impact == .INITIAL or impact == .BOTH) {
            self.initial_severity_flag = flag;
        }
        if (impact == .FINAL or impact == .BOTH) {
            self.final_severity_flag = flag;
        }
    }
};

pub const ProcedureCode = struct {
    value: common.Code,
    attributes: std.ArrayList(Attribute) = .empty,
    flags: std.EnumSet(CodeFlag),
    cluster_ids: std.ArrayList([]const u8) = .empty,
    is_operating_room: bool,
    mdc_suppression: std.bit_set.IntegerBitSet(32),
    is_valid_code: bool,
    drg_impact: GroupingImpact,
    hac_usage_flag: std.EnumSet(ProcedureHacUsage),

    pub fn init(code_str: []const u8) !ProcedureCode {
        var code = common.Code{ .value = [_]u8{0} ** 8 };
        const len = @min(code_str.len, 8);
        @memcpy(code.value[0..len], code_str[0..len]);

        return ProcedureCode{
            .value = code,
            .flags = std.EnumSet(CodeFlag).initEmpty(),
            .is_operating_room = true,
            .mdc_suppression = std.bit_set.IntegerBitSet(32).initEmpty(),
            .is_valid_code = false,
            .drg_impact = .NONE,
            .hac_usage_flag = std.EnumSet(ProcedureHacUsage).initEmpty(),
        };
    }

    pub fn deinit(self: *ProcedureCode, allocator: std.mem.Allocator) void {
        self.attributes.deinit(allocator);
        self.cluster_ids.deinit(allocator);
    }

    pub fn is(self: ProcedureCode, flag: CodeFlag) bool {
        return self.flags.contains(flag);
    }

    pub fn mark(self: *ProcedureCode, flag: CodeFlag) void {
        self.flags.insert(flag);
    }
};

pub const GrouperResult = struct {
    base_drg: ?i32,
    drg: ?i32,
    drg_description: ?[]const u8,
    mdc: ?i32,
    mdc_description: ?[]const u8,
    reroute_mdc_id: ?i32,
    return_code: GrouperReturnCode,
};

pub const ProcessingData = struct {
    principal_dx: ?DiagnosisCode,
    principal_proc: ?ProcedureCode,
    admit_dx: ?DiagnosisCode,
    sdx_codes: std.ArrayList(DiagnosisCode) = .empty,
    procedure_codes: std.ArrayList(ProcedureCode) = .empty,
    clusters: std.ArrayList(ProcedureCode) = .empty,

    age: i32,
    sex: Sex,
    discharge_status: DischargeStatus,

    initial_result: GrouperResult,
    final_result: GrouperResult,
    initial_severity: Severity,
    final_severity: Severity,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ProcessingData {
        return ProcessingData{
            .principal_dx = null,
            .principal_proc = null,
            .admit_dx = null,
            .age = 0,
            .sex = .UNKNOWN,
            .discharge_status = .NONE,
            .initial_result = .{
                .base_drg = null,
                .drg = null,
                .mdc = null,
                .reroute_mdc_id = null,
                .return_code = .OK,
                .drg_description = "",
                .mdc_description = "",
            },
            .final_result = .{
                .base_drg = null,
                .drg = null,
                .mdc = null,
                .reroute_mdc_id = null,
                .return_code = .OK,
                .drg_description = "",
                .mdc_description = "",
            },
            .initial_severity = .NONE,
            .final_severity = .NONE,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ProcessingData) void {
        if (self.principal_dx) |*dx| dx.deinit(self.allocator);
        if (self.principal_proc) |*pr| pr.deinit(self.allocator);
        if (self.admit_dx) |*dx| dx.deinit(self.allocator);

        for (self.sdx_codes.items) |*dx| dx.deinit(self.allocator);
        self.sdx_codes.deinit(self.allocator);

        for (self.procedure_codes.items) |*pr| pr.deinit(self.allocator);
        self.procedure_codes.deinit(self.allocator);

        for (self.clusters.items) |*pr| pr.deinit(self.allocator);
        self.clusters.deinit(self.allocator);
    }
};

pub const GroupingContext = struct {
    pre_match: ?formula.DrgFormula = null,
    reroute_match: ?formula.DrgFormula = null,
    pdx_match: ?formula.DrgFormula = null,

    pub fn hasMatch(self: GroupingContext) bool {
        return self.pre_match != null or self.reroute_match != null or self.pdx_match != null;
    }
};

pub const ProcessingContext = struct {
    data: *ProcessingData,
    runtime: RuntimeOptions,
    initial_grouping_context: GroupingContext,
    final_grouping_context: GroupingContext,
    initial_mdc: std.ArrayList(i32) = .empty,
    final_mdc: std.ArrayList(i32) = .empty,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, data: *ProcessingData, runtime: RuntimeOptions) ProcessingContext {
        return ProcessingContext{
            .data = data,
            .runtime = runtime,
            .initial_grouping_context = .{},
            .final_grouping_context = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ProcessingContext) void {
        self.initial_mdc.deinit(self.allocator);
        self.final_mdc.deinit(self.allocator);
    }
};

test "models basic usage" {
    const allocator = std.testing.allocator;

    // Test DiagnosisCode
    var dx = try DiagnosisCode.init("A001", 'Y');
    defer dx.deinit(allocator);

    try dx.attributes.append(allocator, Attribute{ .list_name = "test_list" });
    try std.testing.expectEqual(dx.attributes.items.len, 1);
    try std.testing.expectEqualStrings(dx.attributes.items[0].list_name, "test_list");

    dx.mark(.AFFECTS_DRG);
    try std.testing.expect(dx.is(.AFFECTS_DRG));
    dx.unMark(.AFFECTS_DRG);
    try std.testing.expect(!dx.is(.AFFECTS_DRG));

    // Test ProcedureCode
    var proc = try ProcedureCode.init("P001");
    defer proc.deinit(allocator);

    try proc.cluster_ids.append(allocator, "cluster1");
    try std.testing.expectEqual(proc.cluster_ids.items.len, 1);

    // Test ProcessingData
    var data = ProcessingData.init(allocator);
    defer data.deinit();

    try data.sdx_codes.append(allocator, try DiagnosisCode.init("B002", 'N'));
    try std.testing.expectEqual(data.sdx_codes.items.len, 1);

    // Test ProcessingContext
    var context = ProcessingContext.init(allocator, &data, .{});
    defer context.deinit();

    try context.initial_mdc.append(allocator, 1);
    try std.testing.expectEqual(context.initial_mdc.items.len, 1);
}
