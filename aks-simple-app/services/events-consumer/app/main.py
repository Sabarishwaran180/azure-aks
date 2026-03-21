from __future__ import annotations

import json
import os
from collections import deque
from threading import Event, Lock, Thread
from typing import Any

from azure.eventhub import EventHubConsumerClient
from fastapi import FastAPI
from opentelemetry import trace
from opentelemetry.propagate import extract

from app.telemetry import configure_telemetry

app = FastAPI(title="Events Consumer API", version="1.0.0")
telemetry_enabled = configure_telemetry(app, "events-consumer")
tracer = trace.get_tracer(__name__)


class EventStore:
    def __init__(self, max_items: int = 20) -> None:
        self._events: deque[dict[str, Any]] = deque(maxlen=max_items)
        self._lock = Lock()

    def add(self, event: dict[str, Any]) -> None:
        with self._lock:
            self._events.appendleft(event)

    def list(self) -> list[dict[str, Any]]:
        with self._lock:
            return list(self._events)


class EventHubListener:
    def __init__(self) -> None:
        self._connection_string = os.getenv("EVENTS_EVENTHUB_CONNECTION_STRING", "").strip()
        self._eventhub_name = os.getenv("EVENTS_EVENTHUB_NAME", "").strip()
        self._consumer_group = os.getenv("EVENTS_CONSUMER_GROUP", "$Default").strip()
        if not self._connection_string or not self._eventhub_name:
            raise RuntimeError(
                "EVENTS_EVENTHUB_CONNECTION_STRING and EVENTS_EVENTHUB_NAME are required"
            )
        self._client = EventHubConsumerClient.from_connection_string(
            conn_str=self._connection_string,
            consumer_group=self._consumer_group,
            eventhub_name=self._eventhub_name,
        )
        self._store = EventStore()
        self._stop_event = Event()
        self._thread: Thread | None = None

    @property
    def eventhub_name(self) -> str:
        return self._eventhub_name

    @property
    def consumer_group(self) -> str:
        return self._consumer_group

    def events(self) -> list[dict[str, Any]]:
        return self._store.list()

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._stop_event.clear()
        self._thread = Thread(target=self._receive, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop_event.set()
        self._client.close()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=5)

    def _receive(self) -> None:
        try:
            self._client.receive(
                on_event=self._on_event,
                starting_position="-1",
            )
        except Exception:
            if not self._stop_event.is_set():
                raise

    def _on_event(self, partition_context: Any, event: Any) -> None:
        properties = _decode_properties(getattr(event, "properties", None) or {})
        context = extract(properties)
        with tracer.start_as_current_span("eventhub.consume order-created", context=context) as span:
            span.set_attribute("messaging.system", "eventhubs")
            span.set_attribute("messaging.destination", self._eventhub_name)
            span.set_attribute("messaging.operation", "process")
            span.set_attribute("messaging.event_hubs.partition_id", partition_context.partition_id)
            payload = event.body_as_str(encoding="UTF-8")
            try:
                data = json.loads(payload)
            except json.JSONDecodeError:
                data = {"raw": payload}
            event_data = data.get("data", data)
            if isinstance(event_data, dict) and "orderId" in event_data:
                span.set_attribute("order.id", event_data["orderId"])
            self._store.add(
                {
                    "partitionId": partition_context.partition_id,
                    "sequenceNumber": event.sequence_number,
                    "offset": event.offset,
                    "enqueuedTime": event.enqueued_time.isoformat(),
                    "data": event_data,
                    "eventType": data.get("eventType", "unknown"),
                    "traceparent": properties.get("traceparent"),
                }
            )


listener = EventHubListener()


@app.on_event("startup")
def startup() -> None:
    listener.start()


@app.on_event("shutdown")
def shutdown() -> None:
    listener.stop()


@app.get("/")
def root() -> dict[str, str]:
    return {"message": "Events Consumer API is running"}


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {
        "status": "ok",
        "service": "events-consumer",
        "eventHubName": listener.eventhub_name,
        "consumerGroup": listener.consumer_group,
        "telemetry": "enabled" if telemetry_enabled else "disabled",
    }


@app.get("/events")
def get_events() -> dict[str, object]:
    return {
        "eventHubName": listener.eventhub_name,
        "consumerGroup": listener.consumer_group,
        "events": listener.events(),
    }


def _decode_properties(properties: dict[Any, Any]) -> dict[str, str]:
    decoded: dict[str, str] = {}
    for key, value in properties.items():
        decoded_key = key.decode("utf-8") if isinstance(key, bytes) else str(key)
        decoded_value = value.decode("utf-8") if isinstance(value, bytes) else str(value)
        decoded[decoded_key] = decoded_value
    return decoded
