from fastapi import FastAPI
from opentelemetry import trace
from pydantic import BaseModel, Field

from app.db import build_products_repository
from app.telemetry import configure_telemetry

app = FastAPI(title="Products API", version="1.0.0")
repository = build_products_repository()
telemetry_enabled = configure_telemetry(app, "products-api", repository.engine)
tracer = trace.get_tracer(__name__)


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
    return {
        "status": "ok",
        "service": "products-api",
        "storage": repository.storage_mode,
        "telemetry": "enabled" if telemetry_enabled else "disabled",
    }


@app.get("/items")
def list_items() -> dict[str, list[dict[str, int | float | str]]]:
    with tracer.start_as_current_span("products.list_items") as span:
        span.set_attribute("app.operation", "list_products")
        items = repository.list_items()
        span.set_attribute("products.count", len(items))
        return {"items": items}


@app.post("/items", status_code=201)
def create_item(item: ProductCreate) -> dict[str, int | float | str]:
    with tracer.start_as_current_span("products.create_item") as span:
        span.set_attribute("app.operation", "create_product")
        span.set_attribute("product.name", item.name)
        created_item = repository.create_item(item.name, item.price)
        span.set_attribute("product.id", created_item["id"])
        return created_item
