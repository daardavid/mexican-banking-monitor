from __future__ import annotations

from decimal import Decimal


def safe_ratio(numerator: Decimal | None, denominator: Decimal | None) -> Decimal | None:
    """Return an exact ratio, or None when the metric is not economically defined."""
    if numerator is None or denominator is None or denominator == 0:
        return None
    return numerator / denominator


def year_over_year_growth(current: Decimal | None, prior_year: Decimal | None) -> Decimal | None:
    ratio = safe_ratio(current, prior_year)
    return None if ratio is None else ratio - Decimal(1)


def net_interest_margin(
    net_interest_income_ttm: Decimal | None,
    average_earning_assets: Decimal | None,
) -> Decimal | None:
    return safe_ratio(net_interest_income_ttm, average_earning_assets)


def return_on_assets(
    net_income_ttm: Decimal | None,
    average_total_assets: Decimal | None,
) -> Decimal | None:
    return safe_ratio(net_income_ttm, average_total_assets)


def return_on_equity(
    net_income_ttm: Decimal | None,
    average_equity: Decimal | None,
) -> Decimal | None:
    return safe_ratio(net_income_ttm, average_equity)


def npl_ratio(stage_3_loans: Decimal | None, gross_loans: Decimal | None) -> Decimal | None:
    return safe_ratio(stage_3_loans, gross_loans)


def coverage_ratio(
    credit_loss_allowance: Decimal | None,
    stage_3_loans: Decimal | None,
) -> Decimal | None:
    return safe_ratio(credit_loss_allowance, stage_3_loans)


def cost_of_risk(
    provision_expense_ttm: Decimal | None,
    average_gross_loans: Decimal | None,
) -> Decimal | None:
    return safe_ratio(provision_expense_ttm, average_gross_loans)


def loans_to_deposits(
    gross_loans: Decimal | None,
    traditional_deposits: Decimal | None,
) -> Decimal | None:
    return safe_ratio(gross_loans, traditional_deposits)
