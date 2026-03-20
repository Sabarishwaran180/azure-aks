from fastapi import FastAPI
from pydantic import BaseModel, Field

from app.db import build_orders_repository
from app.eventhub import EventHubPublisher

app = FastAPI(title="Orders API", version="1.0.0")
repository = build_orders_repository()
publisher = EventHubPublisher()


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
    }


@app.get("/status")
def order_status() -> dict[str, list[dict[str, str]]]:
    return {"orders": repository.list_orders()}


@app.post("/orders", status_code=201)
def create_order(order: OrderCreate) -> dict[str, object]:
    created_order = repository.create_order(order.status)
    publisher.publish_order_created(created_order)
    return {
        "order": created_order,
        "storedInDb": True,
        "publishedToEventHub": True,
        "eventHubName": publisher.eventhub_name,
    }
