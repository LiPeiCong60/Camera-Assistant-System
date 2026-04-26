"""FastAPI app entrypoint for device_runtime local control API."""

from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from device_runtime.api.routes.ai import router as ai_router
from device_runtime.api.routes.capture import router as capture_router
from device_runtime.api.routes.control import router as control_router
from device_runtime.api.routes.session import router as session_router
from device_runtime.api.routes.status import router as status_router
from device_runtime.api.routes.stream import router as stream_router
from device_runtime.api.routes.templates import router as templates_router
from device_runtime.api.routes.webrtc import close_webrtc_peers, router as webrtc_router

app = FastAPI(title="云影随行 Device Runtime API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(ai_router)
app.include_router(capture_router)
app.include_router(session_router)
app.include_router(control_router)
app.include_router(status_router)
app.include_router(stream_router)
app.include_router(templates_router)
app.include_router(webrtc_router)


@app.on_event("shutdown")
async def shutdown_webrtc_peers() -> None:
    await close_webrtc_peers()
