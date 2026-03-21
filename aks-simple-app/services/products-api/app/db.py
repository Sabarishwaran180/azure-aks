from __future__ import annotations

import os
from urllib.parse import quote_plus

from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

DEFAULT_PRODUCTS = [
    {"id": 1, "name": "AKS Starter", "price": 19.99},
    {"id": 2, "name": "FastAPI Guide", "price": 29.99},
    {"id": 3, "name": "Kubernetes Notes", "price": 14.99},
]


class SqlProductsRepository:
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
                    IF OBJECT_ID('dbo.products', 'U') IS NULL
                    BEGIN
                        CREATE TABLE dbo.products (
                            id INT IDENTITY(1,1) PRIMARY KEY,
                            name NVARCHAR(255) NOT NULL,
                            price DECIMAL(10,2) NOT NULL
                        )
                    END
                    """
                )
            )
            count = connection.execute(text("SELECT COUNT(1) FROM dbo.products")).scalar_one()
            if count == 0:
                connection.execute(
                    text("INSERT INTO dbo.products (name, price) VALUES (:name, :price)"),
                    [{"name": item["name"], "price": item["price"]} for item in DEFAULT_PRODUCTS],
                )

    def list_items(self) -> list[dict[str, int | float | str]]:
        with self._engine.connect() as connection:
            rows = connection.execute(
                text("SELECT id, name, price FROM dbo.products ORDER BY id")
            ).mappings()
            return [
                {"id": row["id"], "name": row["name"], "price": float(row["price"])}
                for row in rows
            ]

    def create_item(self, name: str, price: float) -> dict[str, int | float | str]:
        with self._engine.begin() as connection:
            row = connection.execute(
                text(
                    """
                    INSERT INTO dbo.products (name, price)
                    OUTPUT INSERTED.id, INSERTED.name, INSERTED.price
                    VALUES (:name, :price)
                    """
                ),
                {"name": name, "price": round(price, 2)},
            ).mappings().one()
            return {"id": row["id"], "name": row["name"], "price": float(row["price"])}


def build_products_repository() -> SqlProductsRepository:
    connection_string = os.getenv("PRODUCTS_SQL_CONNECTION_STRING", "").strip()
    if not connection_string:
        raise RuntimeError("PRODUCTS_SQL_CONNECTION_STRING is required")
    return SqlProductsRepository(connection_string)


def _create_engine(connection_string: str) -> Engine:
    return create_engine(
        f"mssql+pyodbc:///?odbc_connect={quote_plus(connection_string)}",
        pool_pre_ping=True,
    )
