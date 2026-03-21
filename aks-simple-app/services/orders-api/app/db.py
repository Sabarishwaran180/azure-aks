from __future__ import annotations

import os
from datetime import datetime
from urllib.parse import quote_plus
from uuid import uuid4

from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

DEFAULT_ORDERS = [
    {"orderId": "ORD-1001", "status": "processing"},
    {"orderId": "ORD-1002", "status": "shipped"},
    {"orderId": "ORD-1003", "status": "delivered"},
]


class SqlOrdersRepository:
    storage_mode = "sql"

    def __init__(self, connection_string: str) -> None:
        self._engine = _create_engine(connection_string)

    @property
    def engine(self) -> Engine:
        return self._engine

    def initialize(self) -> None:
        with self._engine.begin() as connection:
            connection.execute(
                text(
                    """
                    IF OBJECT_ID('dbo.orders', 'U') IS NULL
                    BEGIN
                        CREATE TABLE dbo.orders (
                            order_id NVARCHAR(40) PRIMARY KEY,
                            status NVARCHAR(50) NOT NULL,
                            created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
                        )
                    END
                    """
                )
            )
            count = connection.execute(text("SELECT COUNT(1) FROM dbo.orders")).scalar_one()
            if count == 0:
                connection.execute(
                    text("INSERT INTO dbo.orders (order_id, status) VALUES (:order_id, :status)"),
                    [
                        {"order_id": order["orderId"], "status": order["status"]}
                        for order in DEFAULT_ORDERS
                    ],
                )

    def list_orders(self) -> list[dict[str, str]]:
        with self._engine.connect() as connection:
            rows = connection.execute(
                text("SELECT order_id, status FROM dbo.orders ORDER BY created_at DESC, order_id DESC")
            ).mappings()
            return [{"orderId": row["order_id"], "status": row["status"]} for row in rows]

    def create_order(self, status: str) -> dict[str, str]:
        order_id = _generate_order_id()
        with self._engine.begin() as connection:
            row = connection.execute(
                text(
                    """
                    INSERT INTO dbo.orders (order_id, status)
                    OUTPUT INSERTED.order_id, INSERTED.status, INSERTED.created_at
                    VALUES (:order_id, :status)
                    """
                ),
                {"order_id": order_id, "status": status},
            ).mappings().one()
            return {
                "orderId": row["order_id"],
                "status": row["status"],
                "createdAt": _format_timestamp(row["created_at"]),
            }


def build_orders_repository() -> SqlOrdersRepository:
    connection_string = os.getenv("ORDERS_SQL_CONNECTION_STRING", "").strip()
    if not connection_string:
        raise RuntimeError("ORDERS_SQL_CONNECTION_STRING is required")
    return SqlOrdersRepository(connection_string)


def _create_engine(connection_string: str) -> Engine:
    return create_engine(
        f"mssql+pyodbc:///?odbc_connect={quote_plus(connection_string)}",
        pool_pre_ping=True,
    )


def _generate_order_id() -> str:
    return f"ORD-{uuid4().hex[:8].upper()}"


def _format_timestamp(value: datetime | str | None) -> str:
    if isinstance(value, datetime):
        return value.isoformat() + "Z"
    if value is None:
        return ""
    return str(value)
