from __future__ import annotations

from decimal import Decimal
from itertools import pairwise


def ytd_to_monthly(values: list[Decimal]) -> list[Decimal]:
    """Convert one institution-year's ordered YTD values into monthly flows."""
    if not values:
        return []
    monthly = [values[0]]
    monthly.extend(current - previous for previous, current in pairwise(values))
    return monthly
