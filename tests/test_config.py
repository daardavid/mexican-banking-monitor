from __future__ import annotations

from copy import deepcopy
from datetime import date
from pathlib import Path
from typing import Any

import pytest
import yaml
from typer.testing import CliRunner

from mx_bank_monitor import cli
from mx_bank_monitor.config import ConfigValidationError, load_config_bundle

runner = CliRunner()


def _valid_documents() -> dict[str, dict[str, Any]]:
    scope = "individual_legal_entity"
    return {
        "sources.yml": {
            "schema_version": 2,
            "sources": [
                {
                    "code": "test_source",
                    "definition_version": 1,
                    "label": "Test source",
                    "regulator_code": "cnbv",
                    "country": "MX",
                    "sector": "banca_multiple",
                    "adapter_key": "test_source",
                    "methodological_role": "primary",
                    "formats": ["csv"],
                    "endpoints": [
                        {"kind": "landing_page", "url": "https://example.test/source"}
                    ],
                    "reporting_scope_codes": [scope],
                    "lifecycle": "draft",
                }
            ],
        },
        "institutions.yml": {
            "schema_version": 2,
            "cohorts": [
                {
                    "code": "traditional_bank",
                    "label": "Traditional bank",
                    "definition": "Test editorial cohort.",
                    "lifecycle": "active",
                }
            ],
            "institutions": [],
        },
        "reporting_scopes.yml": {
            "schema_version": 2,
            "reporting_scopes": [
                {
                    "code": scope,
                    "definition_version": 1,
                    "label": "Individual legal entity",
                    "definition": "One regulated legal entity.",
                    "rationale": "Approved test scope.",
                    "lifecycle": "active",
                }
            ],
        },
        "concepts.yml": {
            "schema_version": 2,
            "concepts": [
                {
                    "code": "gross_loans",
                    "definition_version": 1,
                    "label": "Gross loans",
                    "definition": "Gross loan stock.",
                    "data_nature": "stock",
                    "period_kind": "instant",
                    "canonical_unit_code": "MXN",
                    "reporting_scope_codes": [scope],
                    "lifecycle": "active",
                },
                {
                    "code": "traditional_deposits",
                    "definition_version": 1,
                    "label": "Traditional deposits",
                    "definition": "Deposit stock.",
                    "data_nature": "stock",
                    "period_kind": "instant",
                    "canonical_unit_code": "MXN",
                    "reporting_scope_codes": [scope],
                    "lifecycle": "active",
                },
            ],
        },
        "mappings.yml": {
            "schema_version": 2,
            "regulatory_concepts": [],
            "mappings": [],
        },
        "metrics.yml": {
            "schema_version": 2,
            "metrics": [
                {
                    "code": "loans_to_deposits",
                    "definition_version": 1,
                    "label": "Loans to deposits",
                    "lifecycle": "draft",
                    "implementation_key": "loans_to_deposits",
                    "inputs": [
                        {
                            "role": "numerator",
                            "canonical_concept_code": "gross_loans",
                            "reporting_scope_code": scope,
                        },
                        {
                            "role": "denominator",
                            "canonical_concept_code": "traditional_deposits",
                            "reporting_scope_code": scope,
                        },
                    ],
                    "reporting_scope_rule": "exact",
                    "output": {
                        "unit_code": "ratio",
                        "display_format": "percent",
                        "display_decimal_places": 2,
                    },
                    "frequency": "monthly",
                    "rounding": {
                        "mode": "ROUND_HALF_EVEN",
                        "calculation_decimal_places": 18,
                    },
                    "methodology_description": "Descriptive text only.",
                }
            ],
        },
    }


def _write_bundle(root: Path, documents: dict[str, dict[str, Any]]) -> None:
    root.mkdir(parents=True, exist_ok=True)
    for filename, document in documents.items():
        (root / filename).write_text(
            yaml.safe_dump(document, sort_keys=False), encoding="utf-8"
        )


def _mapping() -> dict[str, Any]:
    return {
        "source_code": "test_source",
        "regulatory_concept_code": "source_gross_loans",
        "regulatory_concept_definition_version": 1,
        "canonical_concept_code": "gross_loans",
        "reporting_scope_code": "individual_legal_entity",
        "definition_version": 1,
        "transformation_key": None,
        "comparability": "EXACT",
        "lifecycle": "draft",
        "methodology_notes": "Direct source-to-canonical mapping.",
        "provenance": "Synthetic test evidence.",
        "valid_from": date(2024, 1, 1),
        "valid_to": None,
    }


def _add_regulatory_concept(documents: dict[str, dict[str, Any]]) -> None:
    documents["mappings.yml"]["regulatory_concepts"] = [
        {
            "source_code": "test_source",
            "code": "source_gross_loans",
            "definition_version": 1,
            "label": "Source gross loans",
            "definition": "Synthetic source taxonomy concept.",
            "reporting_scope_codes": ["individual_legal_entity"],
            "lifecycle": "draft",
            "valid_from": date(2024, 1, 1),
            "valid_to": None,
        }
    ]


def _institution(
    code: str,
    label: str,
    *,
    source_code: str = "test_source",
    registration_code: str = "REG-1",
    alias_value: str = "Shared Bank",
    valid_from: date = date(2024, 1, 1),
    valid_to: date | None = None,
) -> dict[str, Any]:
    return {
        "code": code,
        "canonical_label": label,
        "country": "MX",
        "lifecycle": "draft",
        "provenance": "Synthetic test evidence.",
        "registrations": [
            {
                "regulator_code": "cnbv",
                "registration_type": "test_registration",
                "registration_code": registration_code,
                "source_code": source_code,
                "valid_from": valid_from,
                "valid_to": valid_to,
            }
        ],
        "aliases": [
            {
                "value": alias_value,
                "alias_type": "source_label",
                "source_code": source_code,
                "valid_from": valid_from,
                "valid_to": valid_to,
            }
        ],
        "cohorts": [],
    }


def test_repository_config_bundle_is_valid_and_deterministic() -> None:
    repository_root = Path(__file__).resolve().parents[1]

    first = load_config_bundle(repository_root / "config")
    second = load_config_bundle(repository_root / "config")

    assert first.model_dump(mode="json") == second.model_dump(mode="json")
    assert len(first.sources.sources) == 3
    assert first.institutions.institutions == ()
    assert [scope.code for scope in first.reporting_scopes.reporting_scopes] == [
        "individual_legal_entity"
    ]
    assert [concept.code for concept in first.concepts.concepts] == [
        "gross_loans",
        "traditional_deposits",
        "net_income_ytd",
    ]
    assert first.mappings.regulatory_concepts == ()
    assert first.mappings.mappings == ()
    assert [metric.code for metric in first.metrics.metrics] == ["loans_to_deposits"]
    assert "formula:" not in (repository_root / "config" / "metrics.yml").read_text(
        encoding="utf-8"
    )


def test_valid_minimal_zero_institution_bundle(tmp_path: Path) -> None:
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, _valid_documents())

    bundle = load_config_bundle(config_dir)

    assert bundle.institutions.institutions == ()
    assert bundle.mappings.mappings == ()


def test_duplicate_yaml_mapping_key_is_rejected(tmp_path: Path) -> None:
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, _valid_documents())
    (config_dir / "sources.yml").write_text(
        "schema_version: 2\nschema_version: 2\nsources: []\n", encoding="utf-8"
    )

    with pytest.raises(ConfigValidationError, match="duplicate key 'schema_version'"):
        load_config_bundle(config_dir)


def test_unsupported_schema_version_is_rejected(tmp_path: Path) -> None:
    documents = _valid_documents()
    documents["concepts.yml"]["schema_version"] = 1
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    with pytest.raises(ConfigValidationError, match="unsupported schema_version 1; expected 2"):
        load_config_bundle(config_dir)


def test_missing_required_file_is_rejected(tmp_path: Path) -> None:
    documents = _valid_documents()
    del documents["reporting_scopes.yml"]
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    with pytest.raises(ConfigValidationError, match="missing required configuration file"):
        load_config_bundle(config_dir)


def test_extra_unknown_field_is_rejected(tmp_path: Path) -> None:
    documents = _valid_documents()
    documents["sources.yml"]["sources"][0]["secret_token"] = "must-not-be-accepted"
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    with pytest.raises(ConfigValidationError, match="Extra inputs are not permitted") as error:
        load_config_bundle(config_dir)
    assert "must-not-be-accepted" not in str(error.value)


def test_executable_formula_field_is_not_part_of_metric_contract(tmp_path: Path) -> None:
    documents = _valid_documents()
    documents["metrics.yml"]["metrics"][0]["formula"] = "dangerous_expression()"
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    with pytest.raises(ConfigValidationError, match="Extra inputs are not permitted") as error:
        load_config_bundle(config_dir)
    assert "dangerous_expression" not in str(error.value)


def test_malformed_yaml_is_rejected(tmp_path: Path) -> None:
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, _valid_documents())
    (config_dir / "metrics.yml").write_text("metrics: [\n", encoding="utf-8")

    with pytest.raises(ConfigValidationError, match="invalid YAML"):
        load_config_bundle(config_dir)


def test_duplicate_source_code_is_rejected(tmp_path: Path) -> None:
    documents = _valid_documents()
    documents["sources.yml"]["sources"].append(
        deepcopy(documents["sources.yml"]["sources"][0])
    )
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    with pytest.raises(ConfigValidationError, match="duplicate source code: test_source"):
        load_config_bundle(config_dir)


@pytest.mark.parametrize(
    ("field", "invalid_value"),
    [
        ("methodological_role", "unknown_role"),
        ("formats", ["json"]),
    ],
)
def test_invalid_source_vocabularies_are_rejected(
    tmp_path: Path, field: str, invalid_value: object
) -> None:
    documents = _valid_documents()
    documents["sources.yml"]["sources"][0][field] = invalid_value
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    with pytest.raises(ConfigValidationError, match="Input should be"):
        load_config_bundle(config_dir)


@pytest.mark.parametrize(
    ("field", "value"),
    [("regulator_code", "other_regulator"), ("country", "US"), ("sector", "sofipo")],
)
def test_source_product_boundary_is_explicit(
    tmp_path: Path, field: str, value: str
) -> None:
    documents = _valid_documents()
    documents["sources.yml"]["sources"][0][field] = value
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    with pytest.raises(
        ConfigValidationError, match="outside the Mexico/banca multiple v1 boundary"
    ):
        load_config_bundle(config_dir)


def test_invalid_institution_validity_and_unknown_cohort_are_rejected(tmp_path: Path) -> None:
    documents = _valid_documents()
    documents["institutions.yml"]["institutions"] = [
        {
            "code": "test_bank",
            "canonical_label": "Test Bank",
            "country": "MX",
            "lifecycle": "draft",
            "provenance": "Synthetic test evidence.",
            "registrations": [],
            "aliases": [],
            "cohorts": [
                {
                    "cohort_code": "unknown_cohort",
                    "rationale": "Synthetic test.",
                    "valid_from": date(2025, 1, 2),
                    "valid_to": date(2025, 1, 1),
                }
            ],
        }
    ]
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    with pytest.raises(ConfigValidationError, match="valid_from must be on or before valid_to"):
        load_config_bundle(config_dir)

    documents["institutions.yml"]["institutions"][0]["cohorts"][0]["valid_to"] = None
    _write_bundle(config_dir, documents)
    with pytest.raises(ConfigValidationError, match="references unknown cohort unknown_cohort"):
        load_config_bundle(config_dir)


def test_ambiguous_alias_and_registration_identity_are_rejected(tmp_path: Path) -> None:
    documents = _valid_documents()
    documents["institutions.yml"]["institutions"] = [
        _institution("bank_one", "Bank One"),
        _institution("bank_two", "Bank Two"),
    ]
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    with pytest.raises(
        ConfigValidationError, match="duplicate overlapping regulatory registration"
    ):
        load_config_bundle(config_dir)

    documents["institutions.yml"]["institutions"][1]["registrations"] = []
    with pytest.raises(ConfigValidationError, match="ambiguous overlapping alias"):
        _write_bundle(config_dir, documents)
        load_config_bundle(config_dir)


def test_alias_identity_is_source_specific_and_different_aliases_can_coexist(
    tmp_path: Path,
) -> None:
    documents = _valid_documents()
    second_source = deepcopy(documents["sources.yml"]["sources"][0])
    second_source["code"] = "second_source"
    documents["sources.yml"]["sources"].append(second_source)

    bank_one = _institution("bank_one", "Bank One")
    bank_one["aliases"].append(
        {
            "value": "Another Bank One Alias",
            "alias_type": "trade_name",
            "source_code": "test_source",
            "valid_from": date(2024, 1, 1),
            "valid_to": None,
        }
    )
    bank_two = _institution(
        "bank_two",
        "Bank Two",
        source_code="second_source",
        registration_code="REG-2",
    )
    documents["institutions.yml"]["institutions"] = [bank_one, bank_two]
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    bundle = load_config_bundle(config_dir)

    assert [source.adapter_key for source in bundle.sources.sources] == [
        "test_source",
        "test_source",
    ]
    assert len(bundle.institutions.institutions[0].aliases) == 2

    bank_two["aliases"][0]["source_code"] = "test_source"
    _write_bundle(config_dir, documents)
    with pytest.raises(ConfigValidationError, match="ambiguous overlapping alias"):
        load_config_bundle(config_dir)


def test_inclusive_validity_boundaries_are_deterministic(tmp_path: Path) -> None:
    documents = _valid_documents()
    first = _institution(
        "bank_one", "Bank One", valid_to=date(2026, 5, 31)
    )
    second = _institution(
        "bank_two", "Bank Two", valid_from=date(2026, 6, 1)
    )
    first["aliases"] = []
    second["aliases"] = []
    documents["institutions.yml"]["institutions"] = [first, second]
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    load_config_bundle(config_dir)

    first["registrations"][0]["valid_to"] = date(2026, 6, 1)
    _write_bundle(config_dir, documents)
    with pytest.raises(
        ConfigValidationError, match="duplicate overlapping regulatory registration"
    ):
        load_config_bundle(config_dir)


@pytest.mark.parametrize(
    ("target", "value", "message"),
    [
        ("source_code", "unknown_source", "references unknown source unknown_source"),
        (
            "canonical_concept_code",
            "unknown_concept",
            "references unknown canonical concept unknown_concept",
        ),
        (
            "reporting_scope_code",
            "unknown_scope",
            "references unknown reporting scope unknown_scope",
        ),
    ],
)
def test_mapping_unknown_references_are_rejected(
    tmp_path: Path, target: str, value: str, message: str
) -> None:
    documents = _valid_documents()
    _add_regulatory_concept(documents)
    mapping = _mapping()
    mapping[target] = value
    documents["mappings.yml"]["mappings"] = [mapping]
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    with pytest.raises(ConfigValidationError, match=message):
        load_config_bundle(config_dir)


def test_mapping_unknown_regulatory_concept_is_rejected(tmp_path: Path) -> None:
    documents = _valid_documents()
    documents["mappings.yml"]["mappings"] = [_mapping()]
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    with pytest.raises(ConfigValidationError, match="unknown regulatory concept"):
        load_config_bundle(config_dir)


def test_mapping_source_scope_combination_must_be_declared(tmp_path: Path) -> None:
    documents = _valid_documents()
    documents["reporting_scopes.yml"]["reporting_scopes"].append(
        {
            "code": "synthetic_scope",
            "definition_version": 1,
            "label": "Synthetic scope",
            "definition": "A scope used only by isolated tests.",
            "rationale": "Synthetic test fixture.",
            "lifecycle": "draft",
        }
    )
    documents["concepts.yml"]["concepts"][0]["reporting_scope_codes"].append(
        "synthetic_scope"
    )
    _add_regulatory_concept(documents)
    documents["mappings.yml"]["regulatory_concepts"][0]["reporting_scope_codes"].append(
        "synthetic_scope"
    )
    mapping = _mapping()
    mapping["reporting_scope_code"] = "synthetic_scope"
    documents["mappings.yml"]["mappings"] = [mapping]
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    with pytest.raises(ConfigValidationError, match="unsupported by source test_source"):
        load_config_bundle(config_dir)


@pytest.mark.parametrize(
    ("field", "value"),
    [("comparability", "SIMILAR"), ("lifecycle", "published")],
)
def test_invalid_mapping_vocabularies_are_rejected(
    tmp_path: Path, field: str, value: str
) -> None:
    documents = _valid_documents()
    _add_regulatory_concept(documents)
    mapping = _mapping()
    mapping[field] = value
    documents["mappings.yml"]["mappings"] = [mapping]
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    with pytest.raises(ConfigValidationError, match="Input should be"):
        load_config_bundle(config_dir)


def test_duplicate_mapping_version_and_overlapping_active_ranges_are_rejected(
    tmp_path: Path,
) -> None:
    documents = _valid_documents()
    _add_regulatory_concept(documents)
    mapping = _mapping()
    documents["mappings.yml"]["mappings"] = [mapping, deepcopy(mapping)]
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    with pytest.raises(ConfigValidationError, match="duplicate mapping identity/version"):
        load_config_bundle(config_dir)

    mapping["lifecycle"] = "active"
    second = deepcopy(mapping)
    second["definition_version"] = 2
    second["valid_from"] = date(2025, 1, 1)
    documents["mappings.yml"]["mappings"] = [mapping, second]
    _write_bundle(config_dir, documents)
    with pytest.raises(ConfigValidationError, match="overlapping active mapping ranges"):
        load_config_bundle(config_dir)


def test_distinct_mapping_targets_may_share_ranges_and_transformation_keys(
    tmp_path: Path,
) -> None:
    documents = _valid_documents()
    _add_regulatory_concept(documents)
    first = _mapping()
    first["transformation_key"] = "identity"
    second = deepcopy(first)
    second["canonical_concept_code"] = "traditional_deposits"
    documents["mappings.yml"]["mappings"] = [first, second]
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    bundle = load_config_bundle(config_dir)

    assert [mapping.transformation_key for mapping in bundle.mappings.mappings] == [
        "identity",
        "identity",
    ]

    for mapping in documents["mappings.yml"]["mappings"]:
        mapping["lifecycle"] = "active"
        mapping["transformation_key"] = None
    _write_bundle(config_dir, documents)
    load_config_bundle(config_dir)


def test_metric_unknown_input_and_malformed_implementation_key_are_rejected(
    tmp_path: Path,
) -> None:
    documents = _valid_documents()
    metric = documents["metrics.yml"]["metrics"][0]
    metric["inputs"][0]["canonical_concept_code"] = "unknown_concept"
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    with pytest.raises(ConfigValidationError, match="unknown canonical concept unknown_concept"):
        load_config_bundle(config_dir)

    metric["inputs"][0]["canonical_concept_code"] = "gross_loans"
    metric["implementation_key"] = "not-a-valid-key"
    _write_bundle(config_dir, documents)
    with pytest.raises(ConfigValidationError, match="String should match pattern"):
        load_config_bundle(config_dir)


def test_metric_versions_may_share_an_implementation_key(tmp_path: Path) -> None:
    documents = _valid_documents()
    second = deepcopy(documents["metrics.yml"]["metrics"][0])
    second["definition_version"] = 2
    documents["metrics.yml"]["metrics"].append(second)
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    bundle = load_config_bundle(config_dir)

    assert [metric.implementation_key for metric in bundle.metrics.metrics] == [
        "loans_to_deposits",
        "loans_to_deposits",
    ]

    second["definition_version"] = 1
    _write_bundle(config_dir, documents)
    with pytest.raises(ConfigValidationError, match="duplicate metric identity/version"):
        load_config_bundle(config_dir)


def test_scope_is_required_and_never_defaulted(tmp_path: Path) -> None:
    documents = _valid_documents()
    documents["reporting_scopes.yml"]["reporting_scopes"] = []
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    with pytest.raises(ConfigValidationError, match="reporting_scopes must not be empty"):
        load_config_bundle(config_dir)

    documents = _valid_documents()
    del documents["metrics.yml"]["metrics"][0]["inputs"][0]["reporting_scope_code"]
    _write_bundle(config_dir, documents)
    with pytest.raises(ConfigValidationError, match="Field required"):
        load_config_bundle(config_dir)


def test_exact_metric_scope_rule_rejects_mixed_input_scopes(tmp_path: Path) -> None:
    documents = _valid_documents()
    documents["metrics.yml"]["metrics"][0]["inputs"][0][
        "reporting_scope_code"
    ] = "synthetic_scope"
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    with pytest.raises(ConfigValidationError, match="requires one shared input scope"):
        load_config_bundle(config_dir)


def test_active_metric_is_rejected_until_python_registry_exists(tmp_path: Path) -> None:
    documents = _valid_documents()
    documents["metrics.yml"]["metrics"][0]["lifecycle"] = "active"
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    with pytest.raises(
        ConfigValidationError, match="before the executable metric registry exists"
    ):
        load_config_bundle(config_dir)


def test_active_mapping_transformation_is_rejected_until_python_registry_exists(
    tmp_path: Path,
) -> None:
    documents = _valid_documents()
    _add_regulatory_concept(documents)
    mapping = _mapping()
    mapping["lifecycle"] = "active"
    mapping["transformation_key"] = "normalize_source_value"
    documents["mappings.yml"]["mappings"] = [mapping]
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, documents)

    with pytest.raises(
        ConfigValidationError, match="before the executable transformation registry exists"
    ):
        load_config_bundle(config_dir)


def test_validate_config_cli_reports_success_and_clean_failure(tmp_path: Path) -> None:
    config_dir = tmp_path / "config"
    _write_bundle(config_dir, _valid_documents())

    valid = runner.invoke(cli.app, ["validate-config", "--config-dir", str(config_dir)])
    assert valid.exit_code == 0
    assert "config valid: schema_version=2 sources=1 institutions=0" in valid.output

    (config_dir / "concepts.yml").write_text("concepts: [\n", encoding="utf-8")
    invalid = runner.invoke(cli.app, ["validate-config", "--config-dir", str(config_dir)])
    assert invalid.exit_code == 1
    assert "config validation failed" in invalid.output
    assert "invalid YAML" in invalid.output
    assert "Traceback" not in invalid.output
