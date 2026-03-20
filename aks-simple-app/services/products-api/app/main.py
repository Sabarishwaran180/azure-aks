from fastapi import FastAPI

app = FastAPI(title="Products API", version="1.0.0")

PRODUCTS = [
    {"id": 1, "name": "AKS Starter", "price": 19.99},
    {"id": 2, "name": "FastAPI Guide", "price": 29.99},
    {"id": 3, "name": "Kubernetes Notes", "price": 14.99},
]


@app.get("/")
def root() -> dict[str, str]:
    return {"message": "Products API is running"}


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok", "service": "products-api"}


@app.get("/items")
def list_items() -> dict[str, list[dict[str, int | float | str]]]:
    return {"items": PRODUCTS}
