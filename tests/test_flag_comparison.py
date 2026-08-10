"""
Unit tests for the flag-level comparison logic in tests/compare_groupers.py.

These tests do not require the JVM or any test data — they exercise the pure
Python normalization and diffing code by feeding it hand-built canonical
dicts. They are the primary safety net for the v44 HAC behavior changes,
which live in flag output and would be invisible to DRG-only comparison.

Run: python -m pytest tests/test_flag_comparison.py -v
"""

import importlib.util
import os
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
COMPARE_PATH = os.path.join(HERE, "compare_groupers.py")


@pytest.fixture(scope="module")
def helpers():
    """Load the pure-Python helpers from tests/compare_groupers.py without
    triggering the real JPype / msdrg / Zig library imports at the top of
    that file. The fake modules are installed in sys.modules only for the
    duration of this fixture and removed afterwards, so they cannot leak
    into other test modules' imports.
    """
    saved = {name: sys.modules.get(name) for name in ("jpype", "jpype.imports", "msdrg")}

    fake_jpype = type(sys)("jpype")
    fake_jpype_imports = type(sys)("jpype.imports")
    fake_jpype.imports = fake_jpype_imports
    fake_jpype.JClass = lambda *a, **kw: None
    fake_jpype.isJVMStarted = lambda: False
    fake_jpype.startJVM = lambda *a, **kw: None
    fake_msdrg = type(sys)("msdrg")
    sys.modules["jpype"] = fake_jpype
    sys.modules["jpype.imports"] = fake_jpype_imports
    sys.modules["msdrg"] = fake_msdrg

    spec = importlib.util.spec_from_file_location("compare_groupers", COMPARE_PATH)
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
        yield {
            "compare_flags": mod.compare_flags,
            "_normalize_zig_flags": mod._normalize_zig_flags,
            "_diff_dicts": mod._diff_dicts,
        }
    finally:
        for name, original in saved.items():
            if original is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = original


def _empty_flags():
    return {
        "pdx": None,
        "sdx": [],
        "procs": [],
        "grouper_flags": {
            "admit_dx_grouper_flag": "DX_NOT_GIVEN",
            "initial_drg_secondary_dx_cc_mcc": "NONE",
            "final_drg_secondary_dx_cc_mcc": "NONE",
            "num_hac_categories_satisfied": 0,
            "hac_status_value": "NOT_APPLICABLE",
        },
    }


def _dx(code, severity="NEITHER", drg_impact="NONE", poa_error="POA_NOT_CHECKED", hacs=None):
    return {
        "code": code,
        "severity": severity,
        "drg_impact": drg_impact,
        "poa_error": poa_error,
        "hacs": hacs or [],
    }


def _proc(code, is_or=False, drg_impact="NONE", hac_usage=None):
    return {
        "code": code,
        "is_or": is_or,
        "drg_impact": drg_impact,
        "hac_usage": hac_usage or [],
    }


def _hac(number, status, hac_list="", description=""):
    return {
        "hac_number": number,
        "hac_list": hac_list,
        "hac_status": status,
        "description": description,
    }


# ---------------------------------------------------------------------------
# compare_flags
# ---------------------------------------------------------------------------


def test_identical_canonical_dicts_produce_no_diffs(helpers):
    canonical = _empty_flags()
    canonical["pdx"] = _dx("I5020", severity="CC", drg_impact="BOTH")
    canonical["sdx"] = [_dx("E1165", severity="MCC", drg_impact="BOTH")]
    canonical["procs"] = [_proc("02703DZ", is_or=True, drg_impact="BOTH")]
    assert helpers["compare_flags"](canonical, canonical) == []


def test_empty_canonical_dicts_produce_no_diffs(helpers):
    assert helpers["compare_flags"](_empty_flags(), _empty_flags()) == []


def test_pdx_severity_diff_is_detected(helpers):
    java = _empty_flags()
    java["pdx"] = _dx("I5020", severity="CC")
    zig = _empty_flags()
    zig["pdx"] = _dx("I5020", severity="MCC")
    diffs = helpers["compare_flags"](java, zig)
    assert len(diffs) == 1
    assert "pdx.severity" in diffs[0]
    assert "CC" in diffs[0] and "MCC" in diffs[0]


def test_pdx_value_diff_when_missing_on_zig_side(helpers):
    java = _empty_flags()
    java["pdx"] = _dx("I5020")
    zig = _empty_flags()  # pdx is None
    diffs = helpers["compare_flags"](java, zig)
    assert any("pdx" in d and "I5020" in d for d in diffs)


def test_sdx_count_diff_is_detected(helpers):
    java = _empty_flags()
    java["sdx"] = [_dx("A"), _dx("B")]
    zig = _empty_flags()
    zig["sdx"] = [_dx("A")]
    diffs = helpers["compare_flags"](java, zig)
    assert any("sdx" in d and "length" in d for d in diffs)


def test_proc_hac_usage_v440_difference_is_detected(helpers):
    """v440 changes procedure HAC usage flagging — this is the headline test."""
    java = _empty_flags()
    java["procs"] = [_proc("02703DZ", is_or=True, drg_impact="BOTH",
                           hac_usage=["HAC_08", "HAC_12"])]
    zig = _empty_flags()
    # Zig v431 would leave hac_usage empty (criteria-met gate)
    zig["procs"] = [_proc("02703DZ", is_or=True, drg_impact="NONE",
                          hac_usage=[])]
    diffs = helpers["compare_flags"](java, zig)
    # Both hac_usage and drg_impact are expected to differ
    assert any("hac_usage" in d for d in diffs)
    assert any("drg_impact" in d for d in diffs)


def test_hac_number_v440_difference_is_detected(helpers):
    """v440 keeps HAC numbers in flag output where v431 zeroed them."""
    java = _empty_flags()
    java["sdx"] = [_dx("A", hacs=[_hac(8, "HAC_CRITERIA_NOT_MET",
                                        hac_list="hac08")])]
    zig = _empty_flags()
    zig["sdx"] = [_dx("A", hacs=[_hac(0, "HAC_CRITERIA_NOT_MET",
                                        hac_list="hac08")])]
    diffs = helpers["compare_flags"](java, zig)
    assert any("hac_number" in d for d in diffs)


def test_hac_list_ordering_does_not_matter(helpers):
    """HAC entries are sorted by (number, list) before comparison, so the
    source ordering of the Java vs Zig output must not cause false diffs."""
    java = _empty_flags()
    java["sdx"] = [_dx("A", hacs=[
        _hac(12, "HAC_CRITERIA_MET", hac_list="hac12"),
        _hac(8, "HAC_CRITERIA_NOT_MET", hac_list="hac08"),
    ])]
    zig = _empty_flags()
    zig["sdx"] = [_dx("A", hacs=[
        _hac(8, "HAC_CRITERIA_NOT_MET", hac_list="hac08"),
        _hac(12, "HAC_CRITERIA_MET", hac_list="hac12"),
    ])]
    assert helpers["compare_flags"](java, zig) == []


def test_sdx_code_ordering_does_not_matter(helpers):
    """Java and Zig can return secondary diagnoses in different orders. The
    comparison matches by code, so reordering must not produce false diffs.
    """
    java = _empty_flags()
    java["sdx"] = [_dx("A", severity="MCC"), _dx("B", severity="CC")]
    zig = _empty_flags()
    zig["sdx"] = [_dx("B", severity="CC"), _dx("A", severity="MCC")]
    assert helpers["compare_flags"](java, zig) == []


def test_proc_code_ordering_does_not_matter(helpers):
    """Same as sdx — procs are matched by code."""
    java = _empty_flags()
    java["procs"] = [
        _proc("02703DZ", is_or=True, drg_impact="BOTH"),
        _proc("0B114F4", is_or=False, drg_impact="NONE"),
    ]
    zig = _empty_flags()
    zig["procs"] = [
        _proc("0B114F4", is_or=False, drg_impact="NONE"),
        _proc("02703DZ", is_or=True, drg_impact="BOTH"),
    ]
    assert helpers["compare_flags"](java, zig) == []


def test_grouper_flags_diff_is_detected(helpers):
    java = _empty_flags()
    java["grouper_flags"]["hac_status_value"] = "FINAL_DRG_CHANGES"
    zig = _empty_flags()
    zig["grouper_flags"]["hac_status_value"] = "FINAL_DRG_NO_CHANGE"
    diffs = helpers["compare_flags"](java, zig)
    assert any("hac_status_value" in d for d in diffs)


def test_grouper_flags_num_hac_categories_diff_is_detected(helpers):
    java = _empty_flags()
    java["grouper_flags"]["num_hac_categories_satisfied"] = 2
    zig = _empty_flags()
    zig["grouper_flags"]["num_hac_categories_satisfied"] = 3
    diffs = helpers["compare_flags"](java, zig)
    assert any("num_hac_categories_satisfied" in d for d in diffs)


def test_booleans_compared_correctly(helpers):
    java = _empty_flags()
    java["procs"] = [_proc("02703DZ", is_or=True)]
    zig = _empty_flags()
    zig["procs"] = [_proc("02703DZ", is_or=False)]
    diffs = helpers["compare_flags"](java, zig)
    assert any("is_or" in d for d in diffs)


# ---------------------------------------------------------------------------
# _normalize_zig_flags
# ---------------------------------------------------------------------------


def test_normalize_strips_mdc_and_flags_fields(helpers):
    zig_res = {
        "pdx_output": {
            "code": "I5020", "mdc": 5, "severity": "CC", "drg_impact": "BOTH",
            "poa_error": "POA_RECOGNIZED_YES_POA",
            "flags": ["VALID", "MARKED_FOR_FINAL"],
            "hacs": [],
        },
        "sdx_output": [],
        "proc_output": [],
        "grouper_flags": _empty_flags()["grouper_flags"],
    }
    canon = helpers["_normalize_zig_flags"](zig_res)
    assert "mdc" not in canon["pdx"]
    assert "flags" not in canon["pdx"]
    assert canon["pdx"]["code"] == "I5020"
    assert canon["pdx"]["severity"] == "CC"


def test_normalize_strips_sentinel_hac_usage_values(helpers):
    zig_res = {
        "pdx_output": None, "sdx_output": [],
        "proc_output": [{
            "code": "X", "is_or": False, "drg_impact": "NONE",
            "flags": [],
            "hac_usage": ["HAC_08", "BLANK", "HAC_NOT_USED", "HAC_12"],
        }],
        "grouper_flags": _empty_flags()["grouper_flags"],
    }
    canon = helpers["_normalize_zig_flags"](zig_res)
    assert canon["procs"][0]["hac_usage"] == ["HAC_08", "HAC_12"]


def test_normalize_handles_missing_fields_gracefully(helpers):
    """An empty/malformed Zig result should normalize to a comparable empty
    canonical dict without raising."""
    canon = helpers["_normalize_zig_flags"]({})
    assert canon == {
        "pdx": None, "sdx": [], "procs": [],
        "grouper_flags": {},
    }


# ---------------------------------------------------------------------------
# _diff_dicts
# ---------------------------------------------------------------------------


def test_diff_dicts_handles_none_vs_value(helpers):
    assert helpers["_diff_dicts"]("x", None, None) == []
    diffs = helpers["_diff_dicts"]("x", None, 1)
    assert len(diffs) == 1 and "None" in diffs[0] and "1" in diffs[0]


def test_diff_dicts_handles_nested_dicts(helpers):
    diffs = helpers["_diff_dicts"]("", {"a": 1, "b": 2}, {"a": 1, "b": 3})
    assert any("b" in d and "2" in d and "3" in d for d in diffs)


def test_diff_dicts_handles_list_length_mismatch(helpers):
    diffs = helpers["_diff_dicts"]("xs", [1, 2, 3], [1, 2])
    assert any("length" in d for d in diffs)
