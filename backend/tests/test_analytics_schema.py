from datetime import UTC, date, datetime
from pathlib import Path
from uuid import uuid4

from conftest import OWNER
from pglast import parse_sql

from app.schemas import CATEGORIES, CURRENCIES, Expense
from app.services.analytics import Period, aggregate_expenses, period_range


def item(cents, day, currency="USD", category="Food & Drinks"):
    return Expense(
        id=uuid4(),
        user_id=OWNER,
        receipt_id=None,
        client_request_id=uuid4(),
        merchant="Shop",
        transaction_date=day,
        amount_in_cents=cents,
        currency=currency,
        category=category,
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )


def test_periods_leap_year_and_equal_duration():
    selected = period_range(Period.THIS_MONTH, date(2026, 10, 18))
    assert selected.start == date(2026, 10, 1)
    assert selected.end_exclusive == date(2026, 10, 19)
    assert selected.previous.start == date(2026, 9, 13)
    assert selected.previous.end_exclusive == selected.start
    leap = period_range(Period.LAST_MONTH, date(2024, 3, 10))
    assert (leap.end_exclusive - leap.start).days == 29
    assert (leap.previous.end_exclusive - leap.previous.start).days == 29
    year = period_range(Period.LAST_THREE_MONTHS, date(2026, 1, 5))
    assert year.start == date(2025, 11, 1)


def test_report_currency_category_and_previous_period_boundaries():
    report = aggregate_expenses(
        [
            item(6000, date(2026, 10, 1)),
            item(4000, date(2026, 10, 18), category="Shopping"),
            item(20000, date(2026, 9, 13)),
            item(9999, date(2026, 9, 12)),
            item(9999, date(2026, 10, 19)),
            item(9999, date(2026, 10, 18), currency="EUR"),
        ],
        Period.THIS_MONTH,
        "USD",
        date(2026, 10, 18),
    )
    assert report.total_in_cents == 10000
    assert report.previous_total_in_cents == 20000
    assert report.percentage_change == -50
    assert report.transaction_count == 2
    assert report.average_in_cents == 5000
    assert [entry.percentage for entry in report.categories] == [60, 40]
    assert sum(entry.amount_in_cents for entry in report.buckets) == report.total_in_cents
    assert len(report.buckets) == 18


def test_empty_and_zero_filled_months():
    report = aggregate_expenses(
        [item(1, date(2026, 8, 1)), item(2, date(2026, 10, 18))],
        Period.LAST_THREE_MONTHS,
        "USD",
        date(2026, 10, 18),
    )
    assert [entry.amount_in_cents for entry in report.buckets] == [1, 0, 2]
    assert report.average_in_cents == 2  # Round half up, consistent with Flutter.
    assert report.percentage_change is None
    empty = aggregate_expenses([], Period.THIS_YEAR, "USD", date(2026, 10, 18))
    assert empty.total_in_cents == 0
    assert empty.categories == []
    assert empty.percentage_change is None


def test_migration_is_valid_postgresql_and_matches_current_app_enums():
    sql = (
        Path(__file__).parents[1] / "supabase/migrations/202610180001_initial_schema.sql"
    ).read_text()
    assert parse_sql(sql)
    for label in (*CURRENCIES, *CATEGORIES):
        assert f"'{label}'" in sql
