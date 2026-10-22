import calendar
from datetime import date, timedelta
from enum import StrEnum

from pydantic import BaseModel

from ..schemas import CATEGORIES, Currency, Expense


class Period(StrEnum):
    THIS_MONTH = "this_month"
    LAST_MONTH = "last_month"
    LAST_THREE_MONTHS = "last_three_months"
    THIS_YEAR = "this_year"


class DateRange(BaseModel):
    start: date
    end_exclusive: date

    @property
    def previous(self):
        return DateRange(
            start=self.start - (self.end_exclusive - self.start), end_exclusive=self.start
        )


def month_start(today: date, shift: int = 0) -> date:
    index = today.year * 12 + today.month - 1 + shift
    return date(index // 12, index % 12 + 1, 1)


def period_range(period: Period, today: date) -> DateRange:
    tomorrow = today + timedelta(days=1)
    match period:
        case Period.THIS_MONTH:
            return DateRange(start=month_start(today), end_exclusive=tomorrow)
        case Period.LAST_MONTH:
            return DateRange(start=month_start(today, -1), end_exclusive=month_start(today))
        case Period.LAST_THREE_MONTHS:
            return DateRange(start=month_start(today, -2), end_exclusive=tomorrow)
        case Period.THIS_YEAR:
            return DateRange(start=date(today.year, 1, 1), end_exclusive=tomorrow)


class CategoryTotal(BaseModel):
    category: str
    amount_in_cents: int
    percentage: float


class SpendingBucket(BaseModel):
    start: date
    end_exclusive: date
    amount_in_cents: int


class SpendingReport(BaseModel):
    period: Period
    currency: Currency
    date_range: DateRange
    previous_range: DateRange
    total_in_cents: int
    previous_total_in_cents: int
    transaction_count: int
    average_in_cents: int
    percentage_change: float | None
    categories: list[CategoryTotal]
    buckets: list[SpendingBucket]


def aggregate_expenses(
    expenses: list[Expense], period: Period, currency: Currency, today: date
) -> SpendingReport:
    selected = period_range(period, today)
    previous = selected.previous
    current = [
        item
        for item in expenses
        if item.currency == currency
        and selected.start <= item.transaction_date < selected.end_exclusive
    ]
    preceding = sum(
        item.amount_in_cents
        for item in expenses
        if item.currency == currency
        and previous.start <= item.transaction_date < previous.end_exclusive
    )
    total = sum(item.amount_in_cents for item in current)
    monthly = period in {Period.LAST_THREE_MONTHS, Period.THIS_YEAR}
    categories: dict[str, int] = {}
    totals: dict[date, int] = {}
    for item in current:
        category = item.category if item.category in CATEGORIES else "Other"
        categories[category] = categories.get(category, 0) + item.amount_in_cents
        bucket = item.transaction_date.replace(day=1) if monthly else item.transaction_date
        totals[bucket] = totals.get(bucket, 0) + item.amount_in_cents
    buckets = []
    cursor = selected.start
    while cursor < selected.end_exclusive:
        next_date = cursor + timedelta(
            days=calendar.monthrange(cursor.year, cursor.month)[1] if monthly else 1
        )
        buckets.append(
            SpendingBucket(
                start=cursor,
                end_exclusive=min(next_date, selected.end_exclusive),
                amount_in_cents=totals.get(cursor, 0),
            )
        )
        cursor = next_date
    count = len(current)
    return SpendingReport(
        period=period,
        currency=currency,
        date_range=selected,
        previous_range=previous,
        total_in_cents=total,
        previous_total_in_cents=preceding,
        transaction_count=count,
        average_in_cents=(total * 2 + count) // (2 * count) if count else 0,
        percentage_change=(total - preceding) / preceding * 100 if preceding else None,
        categories=[
            CategoryTotal(
                category=name,
                amount_in_cents=amount,
                percentage=amount / total * 100 if total else 0,
            )
            for name, amount in sorted(categories.items(), key=lambda item: (-item[1], item[0]))
        ],
        buckets=buckets,
    )
