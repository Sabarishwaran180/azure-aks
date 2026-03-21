from __future__ import annotations

import json
import os
from typing import Any

from azure.eventhub import EventData, EventHubProducerClient
from opentelemetry import trace
from opentelemetry.propagate import inject


tracer = trace.get_tracer(__name__)


class EventHubPublisher:
    def __init__(self) -> None:
        self._connection_string = os.getenv("ORDERS_EVENTHUB_CONNECTION_STRING", "").strip()
        self._eventhub_name = os.getenv("ORDERS_EVENTHUB_NAME", "").strip()
        if not self.enabled:
            raise RuntimeError(
                "ORDERS_EVENTHUB_CONNECTION_STRING and ORDERS_EVENTHUB_NAME are required"
            )
        self._client = EventHubProducerClient.from_connection_string(
            conn_str=self._connection_string,
            eventhub_name=self._eventhub_name,
        )

    @property
    def enabled(self) -> bool:
        return bool(self._connection_string and self._eventhub_name)

    @property
    def mode(self) -> str:
        return "eventhub"

    @property
    def eventhub_name(self) -> str:
        return self._eventhub_name

    def publish_order_created(self, order: dict[str, Any]) -> None:
        with tracer.start_as_current_span("eventhub.publish order-created") as span:
            span.set_attribute("messaging.system", "eventhubs")
            span.set_attribute("messaging.destination", self._eventhub_name)
            span.set_attribute("messaging.operation", "publish")
            span.set_attribute("order.id", order["orderId"])
            carrier: dict[str, str] = {}
            inject(carrier)
            payload = json.dumps({"eventType": "order-created", "data": order})
            event = EventData(payload)
            event.properties = {"orderId": order["orderId"], **carrier}
            event_batch = self._client.create_batch()
            event_batch.add(event)
            self._client.send_batch(event_batch)

    def close(self) -> None:
        self._client.close()
