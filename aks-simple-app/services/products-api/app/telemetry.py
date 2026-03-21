from __future__ import annotations

import os

from azure.monitor.opentelemetry import configure_azure_monitor
from fastapi import FastAPI
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.logging import LoggingInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from sqlalchemy.engine import Engine

_configured = False


def configure_telemetry(app: FastAPI, service_name: str, engine: Engine | None = None) -> bool:
    connection_string = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING", "").strip()
    if not connection_string:
        return False

    os.environ.setdefault("OTEL_SERVICE_NAME", service_name)
    enable_live_metrics = os.getenv("APPLICATIONINSIGHTS_ENABLE_LIVE_METRICS", "true").lower() == "true"

    global _configured
    if not _configured:
        configure_azure_monitor(
            connection_string=connection_string,
            enable_live_metrics=enable_live_metrics,
        )
        LoggingInstrumentor().instrument(set_logging_format=True)
        _configured = True

    FastAPIInstrumentor.instrument_app(app)
    if engine is not None:
        SQLAlchemyInstrumentor().instrument(engine=engine)

    return True
