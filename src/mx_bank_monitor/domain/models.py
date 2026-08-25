from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
from decimal import Decimal
from enum import StrEnum
from hashlib import sha256


class RegulatorySector(StrEnum):
    BANCA_MULTIPLE = "banca_multiple"
    SOFIPO = "sofipo"


class InstitutionCohort(StrEnum):
    TRADITIONAL_BANK = "traditional_bank"
    DIGITAL_BANK = "digital_bank"
    NICHE_BANK = "niche_bank"
    SOFIPO_DIGITAL = "sofipo_digital"


class SourceKind(StrEnum):
    HISTORICAL_SERIES = "historical_series"
    MONTHLY_BULLETIN = "monthly_bulletin"
    CAPITALIZATION = "capitalization"


@dataclass(frozen=True, slots=True)
class Period:
    """A month represented by its first calendar day."""

    value: date

    def __post_init__(self) -> None:
        if self.value.day != 1:
            raise ValueError("A reporting period must use the first day of the month")

    @classmethod
    def parse(cls, value: str) -> Period:
        return cls(datetime.strptime(value, "%Y-%m").date())

    def __str__(self) -> str:
        return self.value.strftime("%Y-%m")


@dataclass(frozen=True, slots=True)
class SourceArtifact:
    source_kind: SourceKind
    sector: RegulatorySector
    period: Period
    source_url: str
    content: bytes
    retrieved_at: datetime

    @property
    def checksum(self) -> str:
        return sha256(self.content).hexdigest()


@dataclass(frozen=True, slots=True)
class FinancialFact:
    institution_id: str
    period: Period
    concept_code: str
    value_mxn: Decimal
    source_checksum: str
