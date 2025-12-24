from fastapi import FastAPI
import os
import socket
from prometheus_fastapi_instrumentator import Instrumentator 


app = FastAPI()

# Prometheus Metriken aktivieren
Instrumentator().instrument(app).expose(app)

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/info")
def info():
    return {
        "pod": socket.gethostname(),
        "node": os.getenv("NODE_NAME", "unknown"),
        "version": os.getenv("APP_VERSION", "v1")
    }

@app.get("/crash")
def crash():
    os._exit(1)

@app.get("/")
def root():
    return {
        "message": "GitOps with ArgoCD is LIVE! 🚀",
        "status": "deployed via ArgoCD"
    }

@app.get("/version")
def version():
    import os
    return {
        "app_version": os.getenv("APP_VERSION", "v1"),
        "pod": socket.gethostname(),
        "node": os.getenv("NODE_NAME", "unknown")
    }