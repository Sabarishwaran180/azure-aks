from fastapi import FastAPI

app = FastAPI(title="Orders API", version="1.0.0")

ORDERS = [
    {"orderId": "ORD-1001", "status": "processing"},
    {"orderId": "ORD-1002", "status": "shipped"},
    {"orderId": "ORD-1003", "status": "delivered"},
]


@app.get("/")
def root() -> dict[str, str]:
    return {"message": "Orders API is running"}


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok", "service": "orders-api"}


@app.get("/status")
def order_status() -> dict[str, list[dict[str, str]]]:
    return {"orders": ORDERS}
