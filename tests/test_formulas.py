from decimal import Decimal

import pytest

from mx_bank_monitor.domain.formulas import (
    cost_of_risk,
    coverage_ratio,
    loans_to_deposits,
    npl_ratio,
    return_on_equity,
    safe_ratio,
    year_over_year_growth,
)


def test_safe_ratio_preserves_decimal_precision() -> None:
    assert safe_ratio(Decimal("1"), Decimal("3")) == Decimal("1") / Decimal("3")


@pytest.mark.parametrize("denominator", [None, Decimal("0")])
def test_safe_ratio_rejects_missing_or_zero_denominator(denominator: Decimal | None) -> None:
    assert safe_ratio(Decimal("10"), denominator) is None


def test_year_over_year_growth() -> None:
    assert year_over_year_growth(Decimal("125"), Decimal("100")) == Decimal("0.25")


def test_core_bank_ratios() -> None:
    assert return_on_equity(Decimal("20"), Decimal("200")) == Decimal("0.1")
    assert npl_ratio(Decimal("3"), Decimal("100")) == Decimal("0.03")
    assert coverage_ratio(Decimal("6"), Decimal("3")) == Decimal("2")
    assert cost_of_risk(Decimal("2"), Decimal("100")) == Decimal("0.02")
    assert loans_to_deposits(Decimal("80"), Decimal("100")) == Decimal("0.8")
