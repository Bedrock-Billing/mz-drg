"""Python-side tests for the msdrg package."""

import pytest
from msdrg import (
    ClaimInput,
    GroupResult,
    MsdrgGrouper,
    ProcedureInput,
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
