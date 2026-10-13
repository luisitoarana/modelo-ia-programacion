FROM python:3.11-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PYTHONPATH=/workspace
WORKDIR /workspace/backend
RUN apt-get update && apt-get install -y --no-install-recommends build-essential cmake curl && rm -rf /var/lib/apt/lists/*
COPY backend/requirements.txt backend/requirements-lock.txt backend/requirements-local-model.txt ./
RUN pip install --no-cache-dir -r requirements.txt
ARG INSTALL_LOCAL_MODEL=true
RUN if [ "$INSTALL_LOCAL_MODEL" = "true" ]; then CMAKE_ARGS="-DGGML_NATIVE=OFF" pip install --no-cache-dir -r requirements-local-model.txt; fi
COPY backend/app ./app
COPY mcp_server /workspace/mcp_server
COPY knowledge_base /workspace/knowledge_base
RUN python -m pip install --no-cache-dir pip==26.2.1 && useradd --create-home explicador && mkdir -p /workspace/proyectos /workspace/backend/logs && chown -R explicador:explicador /workspace
USER explicador
EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=6 CMD curl -fsS http://127.0.0.1:8000/health || exit 1
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
