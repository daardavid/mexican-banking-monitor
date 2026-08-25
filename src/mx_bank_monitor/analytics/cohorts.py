from __future__ import annotations

from decimal import Decimal

from mx_bank_monitor.domain.formulas import safe_ratio


def weighted_ratio(
    numerators: list[Decimal | None],
    denominators: list[Decimal | None],
) -> Decimal | None:
    """Calculate a cohort ratio from aggregate components, not an average of ratios."""
    valid = [
        (numerator, denominator)
        for numerator, denominator in zip(numerators, denominators, strict=True)
        if numerator is not None and denominator is not None
    ]
    if not valid:
        return None
    return safe_ratio(
        sum((pair[0] for pair in valid), Decimal(0)),
        sum((pair[1] for pair in valid), Decimal(0)),
    )
