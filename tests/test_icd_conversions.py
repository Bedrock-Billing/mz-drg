"""Tests for ICD-10 code conversion feature."""

import pytest
from msdrg import IcdConverter, MsdrgGrouper, create_claim


# ---------------------------------------------------------------------------
# IcdConverter lifecycle
# ---------------------------------------------------------------------------


class TestConverterLifecycle:
    def test_init_and_close(self):
        conv = IcdConverter()
        assert "open" in repr(conv)
        conv.close()
        assert "closed" in repr(conv)

    def test_context_manager(self):
        with IcdConverter() as conv:
            assert conv.ctx is not None

    def test_close_idempotent(self):
        conv = IcdConverter()
        conv.close()
        conv.close()  # should not raise

    def test_convert_after_close_raises(self):
        conv = IcdConverter()
        conv.close()
        with pytest.raises(RuntimeError, match="closed"):
            conv.convert_dx("A000", source_year=2025, target_year=2026)


# ---------------------------------------------------------------------------
# Version/Year helpers
# ---------------------------------------------------------------------------


class TestVersionYear:
    def test_version_to_year(self):
        assert IcdConverter.version_to_year(400) == 2023
        assert IcdConverter.version_to_year(401) == 2023
        assert IcdConverter.version_to_year(410) == 2024
        assert IcdConverter.version_to_year(420) == 2025
        assert IcdConverter.version_to_year(431) == 2026

    def test_version_to_year_invalid(self):
        with pytest.raises(ValueError):
            IcdConverter.version_to_year(999)

    def test_year_to_version(self):
        assert IcdConverter.year_to_version(2023) == 401
        assert IcdConverter.year_to_version(2026) == 431

    def test_year_to_version_invalid(self):
        with pytest.raises(ValueError):
            IcdConverter.year_to_version(2020)


# ---------------------------------------------------------------------------
# Diagnosis code conversion (CM)
# ---------------------------------------------------------------------------


class TestDxConversion:
    """B88.0 splits into B88.01 and B88.09 in FY2026 (effective 2025-10-01)."""

    def test_old_to_new(self):
        """B880 (FY2025) -> B8801 (FY2026)."""
        with IcdConverter() as conv:
            result = conv.convert_dx("B880", source_year=2025, target_year=2026)
            assert result == "B8801"

    def test_new_to_old(self):
        """B8801 (FY2026) -> B880 (FY2025)."""
        with IcdConverter() as conv:
            result = conv.convert_dx("B8801", source_year=2026, target_year=2025)
            assert result == "B880"

    def test_dots_stripped(self):
        """B88.0 with dot still maps correctly."""
        with IcdConverter() as conv:
            result = conv.convert_dx("B88.0", source_year=2025, target_year=2026)
            assert result == "B8801"

    def test_second_split_code(self):
        """B8809 (FY2026) -> B880 (FY2025)."""
        with IcdConverter() as conv:
            result = conv.convert_dx("B8809", source_year=2026, target_year=2025)
            assert result == "B880"

    def test_unchanged_code(self):
        """I5020 has no conversion, returns original."""
        with IcdConverter() as conv:
            result = conv.convert_dx("I5020", source_year=2025, target_year=2026)
            assert result == "I5020"

    def test_same_year_no_conversion(self):
        """Same year returns original."""
        with IcdConverter() as conv:
            result = conv.convert_dx("B880", source_year=2026, target_year=2026)
            assert result == "B880"

    def test_a047_split(self):
        """A04.7 splits into A04.71 and A04.72."""
        with IcdConverter() as conv:
            result = conv.convert_dx("A047", source_year=2025, target_year=2026)
            assert result == "A0471"

    def test_batch(self):
        with IcdConverter() as conv:
            results = conv.convert_dx_batch(
                ["B880", "I5020", "A047"],
                source_year=2025,
                target_year=2026,
            )
            assert len(results) == 3
            assert results[0] == {"original": "B880", "converted": "B8801"}
            assert results[1] == {"original": "I5020", "converted": "I5020"}
            assert results[2] == {"original": "A047", "converted": "A0471"}


# ---------------------------------------------------------------------------
# Procedure code conversion (PCS)
# ---------------------------------------------------------------------------


class TestPrConversion:
    def test_pr_converts(self):
        """PCS conversion data is loaded, 02703DZ maps in FY2025->2026."""
        with IcdConverter() as conv:
            result = conv.convert_pr("02703DZ", source_year=2025, target_year=2026)
            # Should be mapped (PCS has many entries)
            assert isinstance(result, str)
            assert len(result) > 0

    def test_pr_same_year(self):
        with IcdConverter() as conv:
            result = conv.convert_pr("02703DZ", source_year=2026, target_year=2026)
            assert result == "02703DZ"


# ---------------------------------------------------------------------------
# Grouper integration (source_icd_version)
# ---------------------------------------------------------------------------


class TestGrouperConversion:
    def test_no_conversion_when_not_set(self):
        """Without source_icd_version, grouping works as normal."""
        with MsdrgGrouper() as g:
            result = g.group(
                create_claim(
                    version=431,
                    age=65,
                    sex=0,
                    discharge_status=1,
                    pdx="I5020",
                )
            )
            assert result["final_drg"] is not None

    def test_same_year_no_conversion(self):
        """When source equals target year, no conversion needed."""
        with MsdrgGrouper() as g:
            result = g.group(
                {
                    "version": 431,
                    "source_icd_version": 2026,
                    "age": 65,
                    "sex": 0,
                    "discharge_status": 1,
                    "pdx": {"code": "I5020"},
                }
            )
            assert result["final_drg"] is not None

    def test_conversion_changes_code(self):
        """Converting B880 from FY2025 to FY2026 should produce a valid DRG."""
        with MsdrgGrouper() as g:
            result = g.group(
                {
                    "version": 431,
                    "source_icd_version": 2025,
                    "age": 65,
                    "sex": 0,
                    "discharge_status": 1,
                    "pdx": {"code": "B880"},
                }
            )
            # B880 -> B8801, which is a valid PDX
            assert result["final_drg"] is not None

    def test_structured_api_with_conversion(self):
        """Conversion also works with group_structured()."""
        with MsdrgGrouper() as g:
            result = g.group_structured(
                {
                    "version": 431,
                    "source_icd_version": 2025,
                    "age": 65,
                    "sex": 0,
                    "discharge_status": 1,
                    "pdx": {"code": "B880"},
                }
            )
            assert result["final_drg"] is not None

    def test_deep_copy_no_mutation(self):
        """Conversion doesn't mutate the original claim dict."""
        claim = {
            "version": 431,
            "source_icd_version": 2025,
            "age": 65,
            "sex": 0,
            "discharge_status": 1,
            "pdx": {"code": "I5020"},
            "sdx": [{"code": "E1165"}],
        }
        original_pdx = claim["pdx"]["code"]
        original_sdx = claim["sdx"][0]["code"]

        with MsdrgGrouper() as g:
            g.group(claim)

        # Original claim should be unchanged
        assert claim["pdx"]["code"] == original_pdx
        assert claim["sdx"][0]["code"] == original_sdx

    def test_conversions_field_shows_mapped_codes(self):
        """The conversions field in the result shows what was converted."""
        with MsdrgGrouper() as g:
            result = g.group(
                {
                    "version": 431,
                    "source_icd_version": 2025,
                    "age": 65,
                    "sex": 0,
                    "discharge_status": 1,
                    "pdx": {"code": "B880"},
                    "sdx": [{"code": "I5020"}],
                }
            )

        conversions = result.get("conversions", [])
        assert len(conversions) == 1
        assert conversions[0] == {
            "original": "B880",
            "converted": "B8801",
            "code_type": "dx",
            "field": "pdx",
        }

    def test_conversions_empty_when_no_mapping(self):
        """When no codes are converted, conversions is empty."""
        with MsdrgGrouper() as g:
            result = g.group(
                {
                    "version": 431,
                    "source_icd_version": 2025,
                    "age": 65,
                    "sex": 0,
                    "discharge_status": 1,
                    "pdx": {"code": "I5020"},
                }
            )

        assert result.get("conversions", []) == []

    def test_conversions_empty_without_source_version(self):
        """When source_icd_version is not set, conversions is empty."""
        with MsdrgGrouper() as g:
            result = g.group(
                create_claim(
                    version=431,
                    age=65,
                    sex=0,
                    discharge_status=1,
                    pdx="I5020",
                )
            )

        assert result.get("conversions", []) == []

    def test_conversions_with_structured_api(self):
        """Conversions field also populated in group_structured()."""
        with MsdrgGrouper() as g:
            result = g.group_structured(
                {
                    "version": 431,
                    "source_icd_version": 2025,
                    "age": 65,
                    "sex": 0,
                    "discharge_status": 1,
                    "pdx": {"code": "B880"},
                }
            )

        conversions = result.get("conversions", [])
        assert len(conversions) == 1
        assert conversions[0]["original"] == "B880"
        assert conversions[0]["converted"] == "B8801"
