"""Routers FastAPI agrupados por dominio."""

from fastapi import APIRouter

from app.routes import (
    admin,
    agente,
    aprendizaje,
    ai_orchestrator,
    auth,
    chat,
    curriculo,
    dataset,
    evaluation,
    feedback,
    herramientas,
    knowledge,
    knowledge_generation,
    mcp,
    ml_panel,
    proyecto,
    rag,
    research,
)

api_router = APIRouter()
api_router.include_router(auth.router, prefix="/auth", tags=["Autenticación"])
api_router.include_router(admin.router, prefix="/admin", tags=["Administración"])
api_router.include_router(chat.router, prefix="/chat", tags=["Chat"])
api_router.include_router(curriculo.router, prefix="/curriculo", tags=["Currículo y Aprendizaje"])
api_router.include_router(aprendizaje.router, prefix="/aprendizaje", tags=["Práctica Guiada"])
api_router.include_router(ai_orchestrator.router, prefix="/ai", tags=["IA"])
api_router.include_router(dataset.router, prefix="/dataset", tags=["Dataset"])
api_router.include_router(knowledge.router, prefix="/knowledge", tags=["Conocimiento"])
api_router.include_router(
    knowledge_generation.router,
    prefix="/knowledge-gen",
    tags=["Generación de Conocimiento"],
)
api_router.include_router(evaluation.router, prefix="/evaluation", tags=["Evaluación"])
api_router.include_router(ml_panel.router, prefix="/ml", tags=["Panel ML"])
api_router.include_router(proyecto.router, prefix="/proyecto", tags=["Explorador"])
api_router.include_router(herramientas.router, prefix="/herramientas", tags=["Herramientas"])
api_router.include_router(research.router, prefix="/research", tags=["Investigación"])
api_router.include_router(feedback.router, prefix="/feedback", tags=["Feedback (RLHF)"])
api_router.include_router(mcp.router, prefix="/mcp", tags=["MCP (Model Context Protocol)"])
api_router.include_router(agente.router, prefix="/agente", tags=["Agente (Tool Calling)"])
api_router.include_router(rag.router, tags=["RAG (Retrieval)"])
