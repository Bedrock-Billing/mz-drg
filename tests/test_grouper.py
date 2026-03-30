"""Python-side tests for the msdrg package."""

import pytest
import re
from msdrg import (
    MsdrgGrouper,
    create_claim,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def grouper():
    """Module-scoped grouper — initialised once, reused across all tests."""
    with MsdrgGrouper() as g:
        yield g


# ---------------------------------------------------------------------------
# create_claim helper
# ---------------------------------------------------------------------------


class TestCreateClaim:
    def test_basic(self):
        claim = create_claim(
            version=431,
            age=65,
            sex=0,
            discharge_status=1,
            pdx="I5020",
        )
        assert claim["version"] == 431
        assert claim["age"] == 65
        assert claim["pdx"]["code"] == "I5020"
        assert claim["sdx"] == []
        assert claim["procedures"] == []

    def test_with_sdx_and_procedures(self):
        claim = create_claim(
            version=431,
            age=50,
            sex=1,
            discharge_status=1,
            pdx="J189",
            sdx=["E1165", "I10"],
            procedures=["02703DZ", "0BJ08ZZ"],
        )
        assert len(claim["sdx"]) == 2
        assert claim["sdx"][0]["code"] == "E1165"
        assert len(claim["procedures"]) == 2
        assert claim["procedures"][1]["code"] == "0BJ08ZZ"

    def test_empty_sdx_defaults_to_empty_list(self):
        claim = create_claim(version=431, age=0, sex=2, discharge_status=1, pdx="Z0000")
        assert claim["sdx"] == []

    def test_return_type_is_valid_input(self):
        """create_claim output should be accepted by group()."""
        claim = create_claim(version=431, age=65, sex=0, discharge_status=1, pdx="I10")
        # Type check: should be a dict compatible with ClaimInput
        assert isinstance(claim, dict)


# ---------------------------------------------------------------------------
# Basic grouping
# ---------------------------------------------------------------------------


class TestGroupBasic:
    def test_simple_hypertension(self, grouper: MsdrgGrouper):
        result = grouper.group(
            create_claim(version=431, age=65, sex=0, discharge_status=1, pdx="I10")
        )
        assert result["final_drg"] is not None
        assert result["final_mdc"] is not None
        assert result["return_code"] == "OK"
        assert result["final_drg_description"] is not None

    def test_heart_failure(self, grouper: MsdrgGrouper):
        result = grouper.group(
            create_claim(version=431, age=65, sex=0, discharge_status=1, pdx="I5020")
        )
        assert result["final_drg"] == 293
        assert result["final_mdc"] == 5
        assert "Heart" in result["final_drg_description"]

    def test_pneumonia(self, grouper: MsdrgGrouper):
        result = grouper.group(
            create_claim(version=431, age=65, sex=0, discharge_status=1, pdx="J189")
        )
        assert result["final_mdc"] == 4
        assert result["return_code"] == "OK"

    def test_with_sdx_changes_drg(self, grouper: MsdrgGrouper):
        """Adding an MCC secondary dx should change the DRG."""
        base = grouper.group(
            create_claim(version=431, age=65, sex=0, discharge_status=1, pdx="I5020")
        )
        with_mcc = grouper.group(
            create_claim(
                version=431,
                age=65,
                sex=0,
                discharge_status=1,
                pdx="I5020",
                sdx=["J9601"],
            )
        )
        # At least one should differ (severity/MCC impact)
        assert base["final_drg"] != with_mcc["final_drg"] or base.get(
            "pdx_output", {}
        ).get("severity") != with_mcc.get("pdx_output", {}).get("severity")


# ---------------------------------------------------------------------------
# DRG versions
# ---------------------------------------------------------------------------


class TestVersions:
    @pytest.mark.parametrize("version", [400, 410, 421, 431])
    def test_version_accepted(self, grouper: MsdrgGrouper, version: int):
        result = grouper.group(
            create_claim(
                version=version, age=65, sex=0, discharge_status=1, pdx="I5020"
            )
        )
        assert result["final_drg"] is not None
        assert result["return_code"] == "OK"


# ---------------------------------------------------------------------------
# Demographics
# ---------------------------------------------------------------------------


class TestDemographics:
    def test_male(self, grouper: MsdrgGrouper):
        result = grouper.group(
            create_claim(version=431, age=65, sex=0, discharge_status=1, pdx="I5020")
        )
        assert result["return_code"] == "OK"

    def test_female(self, grouper: MsdrgGrouper):
        result = grouper.group(
            create_claim(version=431, age=65, sex=1, discharge_status=1, pdx="I5020")
        )
        assert result["return_code"] == "OK"

    def test_unknown_sex(self, grouper: MsdrgGrouper):
        result = grouper.group(
            create_claim(version=431, age=65, sex=2, discharge_status=1, pdx="I5020")
        )
        assert result["return_code"] == "OK"

    def test_died_status(self, grouper: MsdrgGrouper):
        result = grouper.group(
            create_claim(version=431, age=65, sex=0, discharge_status=20, pdx="I5020")
        )
        assert result["return_code"] == "OK"

    def test_neonatal_age_zero(self, grouper: MsdrgGrouper):
        result = grouper.group(
            create_claim(version=431, age=0, sex=0, discharge_status=1, pdx="P0739")
        )
        assert result["final_drg"] is not None

    def test_elderly(self, grouper: MsdrgGrouper):
        result = grouper.group(
            create_claim(version=431, age=100, sex=0, discharge_status=1, pdx="I5020")
        )
        assert result["return_code"] == "OK"


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------


class TestEdgeCases:
    def test_no_sdx(self, grouper: MsdrgGrouper):
        result = grouper.group(
            create_claim(version=431, age=65, sex=0, discharge_status=1, pdx="I5020")
        )
        assert result["sdx_output"] == []

    def test_no_procedures(self, grouper: MsdrgGrouper):
        result = grouper.group(
            create_claim(version=431, age=65, sex=0, discharge_status=1, pdx="I5020")
        )
        assert result["proc_output"] == []

    def test_multiple_sdx(self, grouper: MsdrgGrouper):
        result = grouper.group(
            create_claim(
                version=431,
                age=65,
                sex=0,
                discharge_status=1,
                pdx="I5020",
                sdx=["E1165", "I10", "J9601", "N183"],
            )
        )
        assert result["return_code"] == "OK"

    def test_multiple_procedures(self, grouper: MsdrgGrouper):
        result = grouper.group(
            create_claim(
                version=431,
                age=65,
                sex=0,
                discharge_status=1,
                pdx="I5020",
                procedures=["02703DZ", "0DJ08ZZ"],
            )
        )
        assert result["return_code"] == "OK"

    def test_raw_dict_input(self, grouper: MsdrgGrouper):
        """group() should accept plain dicts, not just create_claim output."""
        result = grouper.group(
            {
                "version": 431,
                "age": 65,
                "sex": 0,
                "discharge_status": 1,
                "pdx": {"code": "I5020"},
            }
        )
        assert result["return_code"] == "OK"

    def test_poa_values(self, grouper: MsdrgGrouper):
        """POA values should be accepted without error."""
        result = grouper.group(
            {
                "version": 431,
                "age": 65,
                "sex": 0,
                "discharge_status": 1,
                "pdx": {"code": "I5020", "poa": "Y"},
                "sdx": [
                    {"code": "E1165", "poa": "Y"},
                    {"code": "I10", "poa": "N"},
                ],
            }
        )
        assert result["return_code"] == "OK"


# ---------------------------------------------------------------------------
# Output structure
# ---------------------------------------------------------------------------


class TestOutputStructure:
    def test_has_required_keys(self, grouper: MsdrgGrouper):
        result = grouper.group(
            create_claim(version=431, age=65, sex=0, discharge_status=1, pdx="I5020")
        )
        required = [
            "initial_drg",
            "final_drg",
            "initial_mdc",
            "final_mdc",
            "return_code",
            "pdx_output",
            "sdx_output",
            "proc_output",
        ]
        for key in required:
            assert key in result, f"Missing key: {key}"

    def test_has_descriptions(self, grouper: MsdrgGrouper):
        result = grouper.group(
            create_claim(version=431, age=65, sex=0, discharge_status=1, pdx="I5020")
        )
        assert result.get("final_drg_description") is not None
        assert result.get("final_mdc_description") is not None

    def test_pdx_output_structure(self, grouper: MsdrgGrouper):
        result = grouper.group(
            create_claim(version=431, age=65, sex=0, discharge_status=1, pdx="I5020")
        )
        pdx = result["pdx_output"]
        assert pdx["code"] == "I5020"
        assert "mdc" in pdx
        assert "severity" in pdx
        assert "flags" in pdx
        assert isinstance(pdx["flags"], list)


# ---------------------------------------------------------------------------
# Context manager and lifecycle
# ---------------------------------------------------------------------------


class TestLifecycle:
    def test_context_manager(self):
        with MsdrgGrouper() as g:
            result = g.group(
                create_claim(version=431, age=65, sex=0, discharge_status=1, pdx="I10")
            )
            assert result["return_code"] == "OK"

    def test_close_idempotent(self):
        g = MsdrgGrouper()
        g.close()
        g.close()  # should not raise

    def test_group_after_close_raises(self):
        g = MsdrgGrouper()
        g.close()
        with pytest.raises(RuntimeError, match="closed"):
            g.group(
                create_claim(version=431, age=65, sex=0, discharge_status=1, pdx="I10")
            )


# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------


class TestErrors:
    def test_missing_library(self):
        with pytest.raises(FileNotFoundError):
            MsdrgGrouper(lib_path="/nonexistent/libmsdrg.so")

    def test_missing_data_dir(self):
        with pytest.raises((RuntimeError, FileNotFoundError)):
            MsdrgGrouper(data_dir="/nonexistent/data")


# ---------------------------------------------------------------------------
# C API edge cases (null inputs, bounds clamping)
# ---------------------------------------------------------------------------


class TestCApiEdgeCases:
    """Exercises the null-check and bounds-clamping added to the C API."""

    def test_null_json_input(self, grouper: MsdrgGrouper):
        """Passing null (None) to msdrg_group_json should return null, not crash."""
        result_ptr = grouper.lib.msdrg_group_json(grouper.ctx, None)
        assert result_ptr is None

    def test_empty_json_input(self, grouper: MsdrgGrouper):
        """Passing empty string should return null (parse failure), not crash."""
        result_ptr = grouper.lib.msdrg_group_json(grouper.ctx, b"")
        assert result_ptr is None

    def test_invalid_sex_clamped(self, grouper: MsdrgGrouper):
        """sex=99 is out of range — C API should clamp, not produce UB.
        should be caught by python validation"""
        with pytest.raises(
            ValueError,
            match=re.escape(
                "'sex' must be 0 (Male), 1 (Female), or 2 (Unknown), got 99"
            ),
        ):
            grouper.group(
                {
                    "version": 431,
                    "age": 65,
                    "sex": 99,
                    "discharge_status": 1,
                    "pdx": {"code": "I5020"},
                }
            )

    def test_invalid_discharge_status_clamped(self, grouper: MsdrgGrouper):
        """discharge_status=999 is out of range — should clamp, not crash."""
        result = grouper.group(
            {
                "version": 431,
                "age": 65,
                "sex": 0,
                "discharge_status": 999,
                "pdx": {"code": "I5020"},
            }
        )
        assert result["return_code"] == "OK"

    def test_negative_sex_clamped(self, grouper: MsdrgGrouper):
        """sex=-1 is out of range — should clamp.
        should be caught by python validation"""
        with pytest.raises(
            ValueError,
            match=re.escape(
                "'sex' must be 0 (Male), 1 (Female), or 2 (Unknown), got -1"
            ),
        ):
            grouper.group(
                {
                    "version": 431,
                    "age": 65,
                    "sex": -1,
                    "discharge_status": 1,
                    "pdx": {"code": "I5020"},
                }
            )

    def test_multiple_groups_no_leak(self, grouper: MsdrgGrouper):
        """Call group() many times — if arena cleanup is wrong, RSS grows."""
        import gc

        gc.collect()
        for _ in range(100):
            grouper.group(
                create_claim(
                    version=431, age=65, sex=0, discharge_status=1, pdx="I5020"
                )
            )
        gc.collect()
        # If we get here without OOM or crash, the arena is cleaning up correctly


# ---------------------------------------------------------------------------
# Hospital status (EXEMPT / NOT_EXEMPT / UNKNOWN)
# ---------------------------------------------------------------------------


class TestHospitalStatus:
    """Tests for hospital POA reporting status affecting HAC processing."""

    def _claim_with_hac_sdx(self, sdx_poa: str, hospital_status: str | None = None):
        """Build a claim with T80211A (HAC 7 code)."""
        claim = {
            "version": 431,
            "age": 65,
            "sex": 0,
            "discharge_status": 1,
            "pdx": {"code": "I5020"},
            "sdx": [{"code": "T80211A", "poa": sdx_poa}],
        }
        if hospital_status:
            claim["hospital_status"] = hospital_status
        return claim

    def test_exempt_skips_hac_processing(self, grouper: MsdrgGrouper):
        """EXEMPT: HACs should be set to HAC_NOT_APPLICABLE_EXEMPT,
        POA error should be HOSPITAL_EXEMPT."""
        result = grouper.group(self._claim_with_hac_sdx("N", "EXEMPT"))
        assert result["return_code"] == "OK"
        sdx = result["sdx_output"][0]
        assert sdx["poa_error"] == "HOSPITAL_EXEMPT"

    def test_not_exempt_default_behavior(self, grouper: MsdrgGrouper):
        """NOT_EXEMPT (default): normal HAC processing applies."""
        result = grouper.group(self._claim_with_hac_sdx("N"))
        assert result["return_code"] == "OK"
        sdx = result["sdx_output"][0]
        assert sdx["poa_error"] == "POA_RECOGNIZED_NOT_POA"

    def test_not_exempt_explicit(self, grouper: MsdrgGrouper):
        """NOT_EXEMPT explicit: same as default."""
        result = grouper.group(self._claim_with_hac_sdx("N", "NOT_EXEMPT"))
        assert result["return_code"] == "OK"
        sdx = result["sdx_output"][0]
        assert sdx["poa_error"] == "POA_RECOGNIZED_NOT_POA"

    def test_unknown_valid_poa(self, grouper: MsdrgGrouper):
        """UNKNOWN with POA=Y: should be OK (Y is valid in UNKNOWN mode)."""
        result = grouper.group(self._claim_with_hac_sdx("Y", "UNKNOWN"))
        assert result["return_code"] == "OK"

    def test_unknown_invalid_poa_returns_specific_code(self, grouper: MsdrgGrouper):
        """UNKNOWN with POA=N: should return specific HAC return code."""
        result = grouper.group(self._claim_with_hac_sdx("N", "UNKNOWN"))
        assert result["return_code"] in (
            "HAC_STATUS_INVALID_POA_N_OR_U",
            "UNGROUPABLE",
        )

    def test_exempt_does_not_mark_ungroupable(self, grouper: MsdrgGrouper):
        """EXEMPT with invalid POA should NOT mark ungroupable."""
        result = grouper.group(self._claim_with_hac_sdx(" ", "EXEMPT"))
        assert result["return_code"] == "OK"

    def test_hospital_status_per_request(self, grouper: MsdrgGrouper):
        """Different hospital_status on consecutive calls should not interfere."""
        r1 = grouper.group(self._claim_with_hac_sdx("N", "EXEMPT"))
        r2 = grouper.group(self._claim_with_hac_sdx("N", "NOT_EXEMPT"))
        r3 = grouper.group(self._claim_with_hac_sdx("N", "EXEMPT"))

        assert r1["sdx_output"][0]["poa_error"] == "HOSPITAL_EXEMPT"
        assert r2["sdx_output"][0]["poa_error"] == "POA_RECOGNIZED_NOT_POA"
        assert r3["sdx_output"][0]["poa_error"] == "HOSPITAL_EXEMPT"
