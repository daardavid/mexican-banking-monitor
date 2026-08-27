from __future__ import annotations

from datetime import date
from enum import StrEnum
from typing import Annotated, Self

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    HttpUrl,
    Strict,
    StrictInt,
    StringConstraints,
    model_validator,
)

CONFIG_SCHEMA_VERSION = 2

Identifier = Annotated[
    str,
    StringConstraints(strict=True, pattern=r"^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$"),
]
CountryCode = Annotated[str, StringConstraints(strict=True, pattern=r"^[A-Z]{2}$")]
MeasurementUnitCode = Annotated[
    str,
    StringConstraints(strict=True, pattern=r"^[A-Za-z][A-Za-z0-9_]*$"),
]
NonEmptyText = Annotated[str, StringConstraints(strict=True, strip_whitespace=True, min_length=1)]
PositiveVersion = Annotated[StrictInt, Field(ge=1)]
ContractDate = Annotated[date, Strict()]


class DefinitionLifecycle(StrEnum):
    DRAFT = "draft"
    ACTIVE = "active"
    REVIEW_REQUIRED = "review_required"
    RETIRED = "retired"


class Comparability(StrEnum):
    EXACT = "EXACT"
    HARMONIZED = "HARMONIZED"
    PROXY = "PROXY"
    NOT_COMPARABLE = "NOT_COMPARABLE"


class SourceFormat(StrEnum):
    CSV = "csv"
    XLSX = "xlsx"
    PDF = "pdf"


class SourceRole(StrEnum):
    PRIMARY = "primary"
    RECONCILIATION = "reconciliation"
    AUTHORITATIVE_ICAP = "authoritative_icap"


class EndpointKind(StrEnum):
    LANDING_PAGE = "landing_page"
    DOCUMENT_LIBRARY = "document_library"


class AliasType(StrEnum):
    LEGAL_NAME = "legal_name"
    TRADE_NAME = "trade_name"
    SOURCE_LABEL = "source_label"


class ConceptDataNature(StrEnum):
    STOCK = "stock"
    FLOW_YTD = "flow_ytd"


class PeriodKind(StrEnum):
    INSTANT = "instant"
    DURATION = "duration"


class MetricDisplayFormat(StrEnum):
    PERCENT = "percent"


class Frequency(StrEnum):
    MONTHLY = "monthly"


class ReportingScopeRule(StrEnum):
    EXACT = "exact"


class RoundingMode(StrEnum):
    HALF_EVEN = "ROUND_HALF_EVEN"


class ContractModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)


def _duplicate(values: tuple[str, ...]) -> str | None:
    seen: set[str] = set()
    for value in values:
        if value in seen:
            return value
        seen.add(value)
    return None


def _require_unique(values: tuple[str, ...], label: str) -> None:
    duplicate = _duplicate(values)
    if duplicate is not None:
        raise ValueError(f"duplicate {label}: {duplicate}")


def _ranges_overlap(
    left_start: date,
    left_end: date | None,
    right_start: date,
    right_end: date | None,
) -> bool:
    return (left_end is None or right_start <= left_end) and (
        right_end is None or left_start <= right_end
    )


class VersionedDocument(ContractModel):
    schema_version: Annotated[StrictInt, Field(ge=1)]

    @model_validator(mode="after")
    def supported_schema_version(self) -> Self:
        if self.schema_version != CONFIG_SCHEMA_VERSION:
            raise ValueError(
                f"unsupported schema_version {self.schema_version}; "
                f"expected {CONFIG_SCHEMA_VERSION}"
            )
        return self


class ValidityRange(ContractModel):
    valid_from: ContractDate
    valid_to: ContractDate | None = None

    @model_validator(mode="after")
    def ordered_validity(self) -> Self:
        if self.valid_to is not None and self.valid_from > self.valid_to:
            raise ValueError("valid_from must be on or before valid_to")
        return self


class SourceEndpoint(ContractModel):
    kind: EndpointKind
    url: HttpUrl


class SourceDefinition(ContractModel):
    code: Identifier
    definition_version: PositiveVersion
    label: NonEmptyText
    regulator_code: Identifier
    country: CountryCode
    sector: Identifier
    adapter_key: Identifier
    methodological_role: SourceRole
    formats: tuple[SourceFormat, ...]
    endpoints: tuple[SourceEndpoint, ...]
    reporting_scope_codes: tuple[Identifier, ...]
    lifecycle: DefinitionLifecycle

    @model_validator(mode="after")
    def unique_nested_values(self) -> Self:
        if not self.formats:
            raise ValueError("formats must contain at least one supported format")
        _require_unique(tuple(item.value for item in self.formats), "source format")
        if not self.endpoints:
            raise ValueError("endpoints must contain at least one non-secret URL")
        endpoint_keys = tuple(f"{item.kind.value}:{item.url}" for item in self.endpoints)
        _require_unique(endpoint_keys, "source endpoint")
        if not self.reporting_scope_codes:
            raise ValueError("reporting_scope_codes must not be empty")
        _require_unique(self.reporting_scope_codes, "reporting scope reference")
        return self


class SourcesDocument(VersionedDocument):
    sources: tuple[SourceDefinition, ...]

    @model_validator(mode="after")
    def unique_sources(self) -> Self:
        _require_unique(tuple(item.code for item in self.sources), "source code")
        return self


class RegulatoryRegistration(ValidityRange):
    regulator_code: Identifier
    registration_type: Identifier
    registration_code: NonEmptyText
    source_code: Identifier


class InstitutionAlias(ValidityRange):
    value: NonEmptyText
    alias_type: AliasType
    source_code: Identifier


class CohortMembership(ValidityRange):
    cohort_code: Identifier
    rationale: NonEmptyText


class InstitutionDefinition(ContractModel):
    code: Identifier
    canonical_label: NonEmptyText
    country: CountryCode
    lifecycle: DefinitionLifecycle
    provenance: NonEmptyText
    registrations: tuple[RegulatoryRegistration, ...]
    aliases: tuple[InstitutionAlias, ...]
    cohorts: tuple[CohortMembership, ...]


class CohortDefinition(ContractModel):
    code: Identifier
    label: NonEmptyText
    definition: NonEmptyText
    lifecycle: DefinitionLifecycle


class InstitutionsDocument(VersionedDocument):
    cohorts: tuple[CohortDefinition, ...]
    institutions: tuple[InstitutionDefinition, ...]

    @model_validator(mode="after")
    def validate_identity_contracts(self) -> Self:
        _require_unique(tuple(item.code for item in self.cohorts), "cohort code")
        _require_unique(tuple(item.code for item in self.institutions), "institution code")

        known_cohorts = {item.code for item in self.cohorts}
        registrations: list[tuple[str, RegulatoryRegistration]] = []
        aliases: list[tuple[str, InstitutionAlias]] = []
        for institution in self.institutions:
            for membership in institution.cohorts:
                if membership.cohort_code not in known_cohorts:
                    raise ValueError(
                        f"institution {institution.code} references unknown cohort "
                        f"{membership.cohort_code}"
                    )
            registrations.extend((institution.code, item) for item in institution.registrations)
            aliases.extend((institution.code, item) for item in institution.aliases)

        for index, (institution_code, registration) in enumerate(registrations):
            identity = (
                registration.regulator_code,
                registration.registration_type,
                registration.registration_code,
            )
            for other_code, other in registrations[index + 1 :]:
                other_identity = (
                    other.regulator_code,
                    other.registration_type,
                    other.registration_code,
                )
                if identity == other_identity and _ranges_overlap(
                    registration.valid_from,
                    registration.valid_to,
                    other.valid_from,
                    other.valid_to,
                ):
                    raise ValueError(
                        "duplicate overlapping regulatory registration "
                        f"{registration.regulator_code}/{registration.registration_type}/"
                        f"{registration.registration_code} for institutions "
                        f"{institution_code} and {other_code}"
                    )

        for index, (institution_code, alias) in enumerate(aliases):
            alias_identity = (alias.source_code, " ".join(alias.value.split()).casefold())
            for other_code, other_alias in aliases[index + 1 :]:
                other_alias_identity = (
                    other_alias.source_code,
                    " ".join(other_alias.value.split()).casefold(),
                )
                if alias_identity == other_alias_identity and _ranges_overlap(
                    alias.valid_from,
                    alias.valid_to,
                    other_alias.valid_from,
                    other_alias.valid_to,
                ):
                    raise ValueError(
                        f"ambiguous overlapping alias {alias.value!r} for institutions "
                        f"{institution_code} and {other_code}"
                    )
        return self


class ReportingScopeDefinition(ContractModel):
    code: Identifier
    definition_version: PositiveVersion
    label: NonEmptyText
    definition: NonEmptyText
    rationale: NonEmptyText
    lifecycle: DefinitionLifecycle


class ReportingScopesDocument(VersionedDocument):
    reporting_scopes: tuple[ReportingScopeDefinition, ...]

    @model_validator(mode="after")
    def unique_scopes(self) -> Self:
        _require_unique(
            tuple(item.code for item in self.reporting_scopes), "reporting scope code"
        )
        if not self.reporting_scopes:
            raise ValueError("reporting_scopes must not be empty")
        return self


class CanonicalConceptDefinition(ContractModel):
    code: Identifier
    definition_version: PositiveVersion
    label: NonEmptyText
    definition: NonEmptyText
    data_nature: ConceptDataNature
    period_kind: PeriodKind
    canonical_unit_code: MeasurementUnitCode
    reporting_scope_codes: tuple[Identifier, ...]
    lifecycle: DefinitionLifecycle

    @model_validator(mode="after")
    def consistent_period_semantics(self) -> Self:
        expected = {
            ConceptDataNature.STOCK: PeriodKind.INSTANT,
            ConceptDataNature.FLOW_YTD: PeriodKind.DURATION,
        }[self.data_nature]
        if self.period_kind != expected:
            raise ValueError(
                f"data_nature {self.data_nature.value} requires period_kind {expected.value}"
            )
        if not self.reporting_scope_codes:
            raise ValueError("reporting_scope_codes must not be empty")
        _require_unique(self.reporting_scope_codes, "reporting scope reference")
        return self


class ConceptsDocument(VersionedDocument):
    concepts: tuple[CanonicalConceptDefinition, ...]

    @model_validator(mode="after")
    def unique_concepts(self) -> Self:
        _require_unique(tuple(item.code for item in self.concepts), "canonical concept code")
        return self


class RegulatoryConceptDefinition(ValidityRange):
    source_code: Identifier
    code: Identifier
    definition_version: PositiveVersion
    label: NonEmptyText
    definition: NonEmptyText
    reporting_scope_codes: tuple[Identifier, ...]
    lifecycle: DefinitionLifecycle


class MappingDefinition(ValidityRange):
    source_code: Identifier
    regulatory_concept_code: Identifier
    regulatory_concept_definition_version: PositiveVersion
    canonical_concept_code: Identifier
    reporting_scope_code: Identifier
    definition_version: PositiveVersion
    transformation_key: Identifier | None
    comparability: Comparability
    lifecycle: DefinitionLifecycle
    methodology_notes: NonEmptyText
    provenance: NonEmptyText


class MappingsDocument(VersionedDocument):
    regulatory_concepts: tuple[RegulatoryConceptDefinition, ...]
    mappings: tuple[MappingDefinition, ...]

    @model_validator(mode="after")
    def validate_mapping_versions(self) -> Self:
        regulatory_identities = tuple(
            f"{item.source_code}:{item.code}:{item.definition_version}"
            for item in self.regulatory_concepts
        )
        _require_unique(regulatory_identities, "regulatory concept identity/version")

        identities = tuple(
            ":".join(
                (
                    item.source_code,
                    item.regulatory_concept_code,
                    str(item.regulatory_concept_definition_version),
                    item.canonical_concept_code,
                    item.reporting_scope_code,
                    str(item.definition_version),
                )
            )
            for item in self.mappings
        )
        _require_unique(identities, "mapping identity/version")

        active = [item for item in self.mappings if item.lifecycle == DefinitionLifecycle.ACTIVE]
        for index, mapping in enumerate(active):
            identity = (
                mapping.source_code,
                mapping.regulatory_concept_code,
                str(mapping.regulatory_concept_definition_version),
                mapping.canonical_concept_code,
                mapping.reporting_scope_code,
            )
            for other in active[index + 1 :]:
                other_identity = (
                    other.source_code,
                    other.regulatory_concept_code,
                    str(other.regulatory_concept_definition_version),
                    other.canonical_concept_code,
                    other.reporting_scope_code,
                )
                if identity == other_identity and _ranges_overlap(
                    mapping.valid_from,
                    mapping.valid_to,
                    other.valid_from,
                    other.valid_to,
                ):
                    raise ValueError(
                        "overlapping active mapping ranges for " + "/".join(identity)
                    )
        return self


class MetricInput(ContractModel):
    role: Identifier
    canonical_concept_code: Identifier
    reporting_scope_code: Identifier


class MetricOutput(ContractModel):
    unit_code: MeasurementUnitCode
    display_format: MetricDisplayFormat
    display_decimal_places: Annotated[StrictInt, Field(ge=0, le=12)]


class MetricRounding(ContractModel):
    mode: RoundingMode
    calculation_decimal_places: Annotated[StrictInt, Field(ge=0, le=18)]


class MetricDefinition(ContractModel):
    code: Identifier
    definition_version: PositiveVersion
    label: NonEmptyText
    lifecycle: DefinitionLifecycle
    implementation_key: Identifier | None
    inputs: tuple[MetricInput, ...]
    reporting_scope_rule: ReportingScopeRule
    output: MetricOutput
    frequency: Frequency
    rounding: MetricRounding
    methodology_description: NonEmptyText

    @model_validator(mode="after")
    def validate_inputs_and_implementation(self) -> Self:
        if not self.inputs:
            raise ValueError("metric inputs must not be empty")
        _require_unique(tuple(item.role for item in self.inputs), "metric input role")
        if self.reporting_scope_rule == ReportingScopeRule.EXACT:
            input_scopes = {item.reporting_scope_code for item in self.inputs}
            if len(input_scopes) != 1:
                raise ValueError("exact reporting_scope_rule requires one shared input scope")
        if self.lifecycle == DefinitionLifecycle.ACTIVE and self.implementation_key is None:
            raise ValueError("active metric requires implementation_key")
        return self


class MetricsDocument(VersionedDocument):
    metrics: tuple[MetricDefinition, ...]

    @model_validator(mode="after")
    def unique_metrics(self) -> Self:
        identities = tuple(
            f"{item.code}:{item.definition_version}" for item in self.metrics
        )
        _require_unique(identities, "metric identity/version")
        return self


class ConfigBundle(ContractModel):
    sources: SourcesDocument
    institutions: InstitutionsDocument
    reporting_scopes: ReportingScopesDocument
    concepts: ConceptsDocument
    mappings: MappingsDocument
    metrics: MetricsDocument

    @property
    def schema_version(self) -> int:
        return CONFIG_SCHEMA_VERSION

    @model_validator(mode="after")
    def validate_cross_references(self) -> Self:
        source_codes = {item.code for item in self.sources.sources}
        scope_codes = {item.code for item in self.reporting_scopes.reporting_scopes}
        concept_codes = {item.code for item in self.concepts.concepts}
        concept_by_code = {item.code: item for item in self.concepts.concepts}
        regulatory_concepts = {
            (item.source_code, item.code, item.definition_version)
            for item in self.mappings.regulatory_concepts
        }
        regulatory_concept_by_key = {
            (item.source_code, item.code, item.definition_version): item
            for item in self.mappings.regulatory_concepts
        }

        def require_reference(kind: str, value: str, known: set[str], owner: str) -> None:
            if value not in known:
                raise ValueError(f"{owner} references unknown {kind} {value}")

        source_by_code = {item.code: item for item in self.sources.sources}
        for source in self.sources.sources:
            if source.regulator_code != "cnbv":
                raise ValueError(
                    f"source {source.code} regulator {source.regulator_code} is outside the "
                    "Mexico/banca multiple v1 boundary"
                )
            if source.country != "MX":
                raise ValueError(
                    f"source {source.code} country {source.country} is outside the "
                    "Mexico/banca multiple v1 boundary"
                )
            if source.sector != "banca_multiple":
                raise ValueError(
                    f"source {source.code} sector {source.sector} is outside the "
                    "Mexico/banca multiple v1 boundary"
                )
            for scope_code in source.reporting_scope_codes:
                require_reference(
                    "reporting scope", scope_code, scope_codes, f"source {source.code}"
                )

        for concept in self.concepts.concepts:
            for scope_code in concept.reporting_scope_codes:
                require_reference(
                    "reporting scope", scope_code, scope_codes, f"concept {concept.code}"
                )

        for institution in self.institutions.institutions:
            if institution.country != "MX":
                raise ValueError(
                    f"institution {institution.code} country {institution.country} is outside "
                    "the Mexico/banca multiple v1 boundary"
                )
            for registration in institution.registrations:
                require_reference(
                    "source",
                    registration.source_code,
                    source_codes,
                    f"institution {institution.code}",
                )
                source = source_by_code[registration.source_code]
                if registration.regulator_code != source.regulator_code:
                    raise ValueError(
                        f"institution {institution.code} registration regulator "
                        f"{registration.regulator_code} does not match source "
                        f"{registration.source_code} regulator {source.regulator_code}"
                    )
            for alias in institution.aliases:
                require_reference(
                    "source", alias.source_code, source_codes, f"institution {institution.code}"
                )

        for regulatory_concept in self.mappings.regulatory_concepts:
            require_reference(
                "source",
                regulatory_concept.source_code,
                source_codes,
                f"regulatory concept {regulatory_concept.code}",
            )
            for scope_code in regulatory_concept.reporting_scope_codes:
                require_reference(
                    "reporting scope",
                    scope_code,
                    scope_codes,
                    f"regulatory concept {regulatory_concept.code}",
                )

        for mapping in self.mappings.mappings:
            owner = (
                f"mapping {mapping.source_code}/{mapping.regulatory_concept_code}/"
                f"{mapping.regulatory_concept_definition_version}/"
                f"{mapping.canonical_concept_code}/{mapping.reporting_scope_code}/"
                f"{mapping.definition_version}"
            )
            require_reference("source", mapping.source_code, source_codes, owner)
            require_reference(
                "canonical concept", mapping.canonical_concept_code, concept_codes, owner
            )
            require_reference(
                "reporting scope", mapping.reporting_scope_code, scope_codes, owner
            )
            regulatory_key = (
                mapping.source_code,
                mapping.regulatory_concept_code,
                mapping.regulatory_concept_definition_version,
            )
            if regulatory_key not in regulatory_concepts:
                raise ValueError(
                    f"{owner} references unknown regulatory concept "
                    f"{mapping.regulatory_concept_code}/"
                    f"{mapping.regulatory_concept_definition_version}"
                )
            source = source_by_code[mapping.source_code]
            if mapping.reporting_scope_code not in source.reporting_scope_codes:
                raise ValueError(
                    f"{owner} uses scope {mapping.reporting_scope_code} unsupported by source "
                    f"{mapping.source_code}"
                )
            regulatory_concept = regulatory_concept_by_key[regulatory_key]
            if mapping.reporting_scope_code not in regulatory_concept.reporting_scope_codes:
                raise ValueError(
                    f"{owner} uses scope {mapping.reporting_scope_code} unsupported by regulatory "
                    f"concept {mapping.regulatory_concept_code}"
                )
            canonical_concept = concept_by_code[mapping.canonical_concept_code]
            if mapping.reporting_scope_code not in canonical_concept.reporting_scope_codes:
                raise ValueError(
                    f"{owner} uses scope {mapping.reporting_scope_code} unsupported by canonical "
                    f"concept {mapping.canonical_concept_code}"
                )

        for metric in self.metrics.metrics:
            for metric_input in metric.inputs:
                require_reference(
                    "canonical concept",
                    metric_input.canonical_concept_code,
                    concept_codes,
                    f"metric {metric.code} input {metric_input.role}",
                )
                require_reference(
                    "reporting scope",
                    metric_input.reporting_scope_code,
                    scope_codes,
                    f"metric {metric.code} input {metric_input.role}",
                )
                concept = concept_by_code[metric_input.canonical_concept_code]
                if metric_input.reporting_scope_code not in concept.reporting_scope_codes:
                    raise ValueError(
                        f"metric {metric.code} input {metric_input.role} uses scope "
                        f"{metric_input.reporting_scope_code} unsupported by canonical concept "
                        f"{metric_input.canonical_concept_code}"
                    )
        return self
