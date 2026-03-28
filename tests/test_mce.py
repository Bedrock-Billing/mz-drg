"""Python tests for the MCE (Medicare Code Editor)."""

import pytest
from msdrg import (
    MceEditor,
    MsdrgGrouper,
    create_mce_input,
    create_claim,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def mce():
    """Module-scoped MCE editor."""
    with MceEditor() as e:
        yield e


@pytest.fixture(scope="module")
def grouper():
    """Module-scoped DRG grouper."""
    with MsdrgGrouper() as g:
        yield g


# ---------------------------------------------------------------------------
# create_mce_input helper
# ---------------------------------------------------------------------------


class TestCreateMceInput:
    def test_basic(self):
        claim = create_mce_input(
            discharge_date=20250101, age=65, sex=0, discharge_status=1, pdx="I5020"
        )
        assert claim["discharge_date"] == 20250101
        assert claim["pdx"]["code"] == "I5020"
        assert claim["sdx"] == []

    def test_with_sdx_and_procedures(self):
        claim = create_mce_input(
            discharge_date=20250101, age=50, sex=1, discharge_status=1,
            pdx="J189", sdx=["E1165"], procedures=["02703DZ"],
        )
        assert len(claim["sdx"]) == 1
        assert len(claim["procedures"]) == 1


# ---------------------------------------------------------------------------
# Basic MCE functionality
# ---------------------------------------------------------------------------


class TestMceBasic:
    def test_valid_claim(self, mce: MceEditor):
        result = mce.edit(create_mce_input(
            discharge_date=20250101, age=65, sex=0, discharge_status=1, pdx="I5020"
        ))
        assert result["edit_type"] == "NONE"
        assert result["edits"] == []

    def test_result_has_required_keys(self, mce: MceEditor):
        result = mce.edit(create_mce_input(
            discharge_date=20250101, age=65, sex=0, discharge_status=1, pdx="I5020"
        ))
        assert "version" in result
        assert "edit_type" in result
        assert "edits" in result

    def test_version_populated(self, mce: MceEditor):
        result = mce.edit(create_mce_input(
            discharge_date=20250101, age=65, sex=0, discharge_status=1, pdx="I5020"
        ))
        assert result["version"] > 0


# ---------------------------------------------------------------------------
# E-code as PDX
# ---------------------------------------------------------------------------


class TestECodeAsPdx:
    def test_ecode_triggers_edit(self, mce: MceEditor):
        result = mce.edit(create_mce_input(
            discharge_date=20250101, age=65, sex=0, discharge_status=1,
            pdx="V0001XA",  # E-code
        ))
        assert result["edit_type"] == "PREPAYMENT"
        edit_names = [e["name"] for e in result["edits"]]
        assert "E_CODE_AS_PDX" in edit_names


# ---------------------------------------------------------------------------
# Sex conflict
# ---------------------------------------------------------------------------


class TestSexConflict:
    def test_female_code_male_sex(self, mce: MceEditor):
        # A34 has "female" flag, active until 20240930
        result = mce.edit({
            "discharge_date": 20240101,  # within active range
            "age": 25, "sex": 0, "discharge_status": 1,
            "pdx": {"code": "I5020"},
            "sdx": [{"code": "A34"}],
            "procedures": [],
        })
        edit_names = [e["name"] for e in result["edits"]]
        assert "SEX_CONFLICT" in edit_names


# ---------------------------------------------------------------------------
# Age conflict
# ---------------------------------------------------------------------------


class TestAgeConflict:
    def test_newborn_code_adult_age(self, mce: MceEditor):
        result = mce.edit(create_mce_input(
            discharge_date=20250101, age=65, sex=0, discharge_status=1,
            pdx="A33",  # Newborn code
        ))
        edit_names = [e["name"] for e in result["edits"]]
        assert "AGE_CONFLICT" in edit_names


# ---------------------------------------------------------------------------
# Unacceptable PDX
# ---------------------------------------------------------------------------


class TestUnacceptablePdx:
    def test_unacceptable_triggers_edit(self, mce: MceEditor):
        result = mce.edit(create_mce_input(
            discharge_date=20250101, age=65, sex=0, discharge_status=1,
            pdx="Z9989",  # Unacceptable PDX
        ))
        edit_names = [e["name"] for e in result["edits"]]
        assert "UNACCEPTABLE_PDX" in edit_names


# ---------------------------------------------------------------------------
# Context manager
# ---------------------------------------------------------------------------


class TestMceLifecycle:
    def test_context_manager(self):
        with MceEditor() as mce:
            result = mce.edit(create_mce_input(
                discharge_date=20250101, age=65, sex=0, discharge_status=1, pdx="I5020"
            ))
            assert result["edit_type"] == "NONE"

    def test_close_idempotent(self):
        mce = MceEditor()
        mce.close()
        mce.close()  # should not raise

    def test_edit_after_close_raises(self):
        mce = MceEditor()
        mce.close()
        with pytest.raises(RuntimeError, match="closed"):
            mce.edit(create_mce_input(
                discharge_date=20250101, age=65, sex=0, discharge_status=1, pdx="I5020"
            ))


# ---------------------------------------------------------------------------
# Unified claim — same dict for MCE and MS-DRG
# ---------------------------------------------------------------------------


class TestUnifiedClaim:
    def test_same_claim_both_tools(self, mce: MceEditor, grouper: MsdrgGrouper):
        """A unified claim works with both MCE and MS-DRG."""
        claim = {
            "version": 431,
            "discharge_date": 20250101,
            "age": 65, "sex": 0, "discharge_status": 1,
            "hospital_status": "NOT_EXEMPT",
            "pdx": {"code": "I5020"},
            "sdx": [{"code": "E1165"}],
            "procedures": [],
        }

        drg_result = grouper.group(claim)
        mce_result = mce.edit(claim)

        assert drg_result["final_drg"] is not None
        assert mce_result["edit_type"] is not None

    def test_ecode_pdx_both_tools(self, mce: MceEditor, grouper: MsdrgGrouper):
        """E-code as PDX triggers MCE edit but still groups in MS-DRG."""
        claim = {
            "version": 431,
            "discharge_date": 20250101,
            "age": 65, "sex": 0, "discharge_status": 1,
            "pdx": {"code": "V0001XA"},
            "sdx": [],
            "procedures": [],
        }

        drg_result = grouper.group(claim)
        mce_result = mce.edit(claim)

        # MS-DRG still produces a DRG
        assert drg_result["final_drg"] is not None
        # MCE flags E_CODE_AS_PDX
        edit_names = [e["name"] for e in mce_result["edits"]]
        assert "E_CODE_AS_PDX" in edit_names


# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------


class TestMceErrors:
    def test_missing_data_dir(self):
        with pytest.raises((RuntimeError, FileNotFoundError)):
            MceEditor(data_dir="/nonexistent/data")
