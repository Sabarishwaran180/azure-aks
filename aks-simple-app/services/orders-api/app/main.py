from fastapi import FastAPI
from opentelemetry import trace
from pydantic import BaseModel, Field

from app.db import build_orders_repository
from app.eventhub import EventHubPublisher
from app.telemetry import configure_telemetry

app = FastAPI(title="Orders API", version="1.0.0")
repository = build_orders_repository()
publisher = EventHubPublisher()
telemetry_enabled = configure_telemetry(app, "orders-api", repository.engine)
tracer = trace.get_tracer(__name__)


class OrderCreate(BaseModel):
    status: str = Field(default="processing", min_length=1, max_length=50)


@app.on_event("startup")
def startup() -> None:
    repository.initialize()


@app.on_event("shutdown")
def shutdown() -> None:
    publisher.close()


@app.get("/")
def root() -> dict[str, str]:
    return {"message": "Orders API is running"}


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {
        "status": "ok",
        "service": "orders-api",
        "storage": repository.storage_mode,
        "eventing": publisher.mode,
        "telemetry": "enabled" if telemetry_enabled else "disabled",
    }


@app.get("/status")
def order_status() -> dict[str, list[dict[str, str]]]:
    with tracer.start_as_current_span("orders.list_orders") as span:
        span.set_attribute("app.operation", "list_orders")
        orders = repository.list_orders()
        span.set_attribute("orders.count", len(orders))
        return {"orders": orders}


@app.post("/orders", status_code=201)
def create_order(order: OrderCreate) -> dict[str, object]:
    with tracer.start_as_current_span("orders.create_order") as span:
        span.set_attribute("app.operation", "create_order")
        span.set_attribute("order.status", order.status)
        created_order = repository.create_order(order.status)
        span.set_attribute("order.id", created_order["orderId"])
        publisher.publish_order_created(created_order)
        span.set_attribute("messaging.destination", publisher.eventhub_name)
        return {
            "order": created_order,
            "storedInDb": True,
            "publishedToEventHub": True,
            "eventHubName": publisher.eventhub_name,
        }
