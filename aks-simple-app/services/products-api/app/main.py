from fastapi import FastAPI
from pydantic import BaseModel, Field

from app.db import build_products_repository

app = FastAPI(title="Products API", version="1.0.0")
repository = build_products_repository()


class ProductCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    price: float = Field(gt=0)


@app.on_event("startup")
def startup() -> None:
    repository.initialize()


@app.get("/")
def root() -> dict[str, str]:
    return {"message": "Products API is running"}


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok", "service": "products-api", "storage": repository.storage_mode}


@app.get("/items")
def list_items() -> dict[str, list[dict[str, int | float | str]]]:
    return {"items": repository.list_items()}


@app.post("/items", status_code=201)
def create_item(item: ProductCreate) -> dict[str, int | float | str]:
    return repository.create_item(item.name, item.price)
