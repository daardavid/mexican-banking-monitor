from datetime import date
from decimal import Decimal

import pytest

from mx_bank_monitor.analytics.cohorts import weighted_ratio
from mx_bank_monitor.domain.models import Period
from mx_bank_monitor.ingestion.ytd import ytd_to_monthly


def test_period_requires_first_day() -> None:
    with pytest.raises(ValueError, match="first day"):
        Period(date(2026, 6, 30))


def test_period_parse() -> None:
    assert str(Period.parse("2026-06")) == "2026-06"


def test_ytd_is_converted_to_monthly_flows() -> None:
    assert ytd_to_monthly(
        [Decimal("10"), Decimal("25"), Decimal("21")]
    ) == [Decimal("10"), Decimal("15"), Decimal("-4")]


def test_cohort_ratio_uses_components_not_average_ratios() -> None:
    result = weighted_ratio(
        [Decimal("10"), Decimal("90")],
        [Decimal("100"), Decimal("300")],
    )
    assert result == Decimal("0.25")
