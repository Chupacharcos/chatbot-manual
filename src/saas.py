"""
saas.py — Sistema multi-tenant para el chatbot RAG.

Gestiona clientes, planes y cuotas de tokens por día usando SQLite.
La DB (chatbot_saas.db) se crea automáticamente en el directorio de trabajo.

Planes disponibles:
  free       → 5.000 tokens/día, 2 sesiones activas, PDF hasta 5 MB
  basic      → 50.000 tokens/día, 10 sesiones activas, PDF hasta 20 MB
  pro        → 500.000 tokens/día, 50 sesiones activas, PDF hasta 50 MB
  enterprise → ilimitado (-1), sesiones ilimitadas, PDF hasta 100 MB

Admin endpoints (protegidos por ADMIN_SECRET env var):
  POST /admin/clients    → crear cliente
  GET  /admin/clients    → listar clientes
  PATCH /admin/clients/{id} → actualizar plan/estado
  GET  /admin/usage      → informe de uso
"""

import os
import sqlite3
import secrets
from datetime import date
from contextlib import contextmanager
from typing import Optional

# ─── Configuración de planes ──────────────────────────────────────────────────

PLANS: dict[str, dict] = {
    "free": {
        "daily_tokens": 5_000,
        "max_sessions": 2,
        "max_pdf_mb": 5,
        "description": "Gratuito — ideal para pruebas",
    },
    "basic": {
        "daily_tokens": 50_000,
        "max_sessions": 10,
        "max_pdf_mb": 20,
        "description": "Básico — pequeñas empresas",
    },
    "pro": {
        "daily_tokens": 500_000,
        "max_sessions": 50,
        "max_pdf_mb": 50,
        "description": "Pro — uso intensivo",
    },
    "enterprise": {
        "daily_tokens": -1,   # -1 = ilimitado
        "max_sessions": -1,
        "max_pdf_mb": 100,
        "description": "Enterprise — sin límites",
    },
}

# ─── Base de datos ────────────────────────────────────────────────────────────

DB_PATH = os.getenv("SAAS_DB_PATH", "chatbot_saas.db")


@contextmanager
def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def init_db():
    """Crea las tablas si no existen y añade el cliente demo por defecto."""
    with get_db() as conn:
        conn.executescript("""
            CREATE TABLE IF NOT EXISTS clients (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                name       TEXT    NOT NULL,
                api_key    TEXT    UNIQUE NOT NULL,
                plan       TEXT    NOT NULL DEFAULT 'free',
                active     INTEGER NOT NULL DEFAULT 1,
                created_at TEXT    NOT NULL DEFAULT (date('now'))
            );

            CREATE TABLE IF NOT EXISTS usage_log (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                client_id  INTEGER NOT NULL,
                log_date   TEXT    NOT NULL,
                tokens_in  INTEGER NOT NULL DEFAULT 0,
                tokens_out INTEGER NOT NULL DEFAULT 0,
                calls      INTEGER NOT NULL DEFAULT 0,
                UNIQUE(client_id, log_date),
                FOREIGN KEY (client_id) REFERENCES clients(id)
            );
        """)

        # Cliente demo (la clave viene de .env o se genera al vuelo)
        demo_key = os.getenv("CLIENT_API_KEY", "")
        if demo_key:
            existing = conn.execute(
                "SELECT id FROM clients WHERE api_key = ?", (demo_key,)
            ).fetchone()
            if not existing:
                conn.execute(
                    "INSERT INTO clients (name, api_key, plan) VALUES (?, ?, ?)",
                    ("Demo Portfolio", demo_key, "pro"),
                )


# ─── Gestión de clientes ──────────────────────────────────────────────────────

def create_client(name: str, plan: str = "free", api_key: str = "") -> dict:
    """Crea un nuevo cliente y devuelve sus datos."""
    if plan not in PLANS:
        raise ValueError(f"Plan inválido: {plan}. Opciones: {list(PLANS)}")
    if not api_key:
        api_key = "ck_" + secrets.token_hex(24)
    new_id = None
    with get_db() as conn:
        cursor = conn.execute(
            "INSERT INTO clients (name, api_key, plan) VALUES (?, ?, ?)",
            (name, api_key, plan),
        )
        new_id = cursor.lastrowid
    # Leer tras el commit
    return get_client_by_id(new_id)


def get_client_by_key(api_key: str) -> Optional[dict]:
    """Busca un cliente activo por su API key."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM clients WHERE api_key = ? AND active = 1",
            (api_key,),
        ).fetchone()
        return dict(row) if row else None


def get_client_by_id(client_id: int) -> Optional[dict]:
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM clients WHERE id = ?", (client_id,)
        ).fetchone()
        return dict(row) if row else None


def list_clients() -> list[dict]:
    with get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM clients ORDER BY id"
        ).fetchall()
        return [dict(r) for r in rows]


def update_client(client_id: int, plan: str = None, active: bool = None) -> dict:
    if plan and plan not in PLANS:
        raise ValueError(f"Plan inválido: {plan}")
    with get_db() as conn:
        if plan is not None:
            conn.execute("UPDATE clients SET plan = ? WHERE id = ?", (plan, client_id))
        if active is not None:
            conn.execute("UPDATE clients SET active = ? WHERE id = ?", (int(active), client_id))
    # Leer tras el commit
    return get_client_by_id(client_id)


# ─── Cuotas y uso de tokens ───────────────────────────────────────────────────

def get_today_usage(client_id: int) -> dict:
    """Devuelve el uso de hoy para un cliente."""
    today = date.today().isoformat()
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM usage_log WHERE client_id = ? AND log_date = ?",
            (client_id, today),
        ).fetchone()
        if row:
            return dict(row)
        return {
            "client_id": client_id,
            "log_date": today,
            "tokens_in": 0,
            "tokens_out": 0,
            "calls": 0,
        }


def check_quota(client: dict) -> tuple[bool, str]:
    """
    Comprueba si el cliente tiene cuota disponible para hoy.
    Retorna (ok: bool, message: str).
    """
    plan = PLANS.get(client["plan"], PLANS["free"])
    daily_limit = plan["daily_tokens"]

    if daily_limit == -1:
        return True, "ok"

    usage = get_today_usage(client["id"])
    total_used = usage["tokens_in"] + usage["tokens_out"]

    if total_used >= daily_limit:
        return False, (
            f"Cuota diaria agotada ({total_used:,}/{daily_limit:,} tokens). "
            f"Se renueva a las 00:00 UTC. Contacta con soporte para ampliar tu plan."
        )
    return True, "ok"


def log_usage(client_id: int, tokens_in: int, tokens_out: int):
    """Registra el uso de tokens de una llamada al LLM."""
    today = date.today().isoformat()
    with get_db() as conn:
        conn.execute("""
            INSERT INTO usage_log (client_id, log_date, tokens_in, tokens_out, calls)
            VALUES (?, ?, ?, ?, 1)
            ON CONFLICT(client_id, log_date) DO UPDATE SET
                tokens_in  = tokens_in  + excluded.tokens_in,
                tokens_out = tokens_out + excluded.tokens_out,
                calls      = calls      + 1
        """, (client_id, today, tokens_in, tokens_out))


# ─── Informes ─────────────────────────────────────────────────────────────────

def get_usage_report(days: int = 7) -> list[dict]:
    """Informe de uso de los últimos N días para todos los clientes."""
    with get_db() as conn:
        rows = conn.execute("""
            SELECT
                c.id,
                c.name,
                c.plan,
                u.log_date,
                COALESCE(u.tokens_in, 0)  AS tokens_in,
                COALESCE(u.tokens_out, 0) AS tokens_out,
                COALESCE(u.calls, 0)      AS calls
            FROM clients c
            LEFT JOIN usage_log u
                ON c.id = u.client_id
                AND u.log_date >= date('now', ?)
            ORDER BY c.id, u.log_date DESC
        """, (f"-{days} days",)).fetchall()
        return [dict(r) for r in rows]


def get_client_remaining(client: dict) -> dict:
    """Tokens restantes hoy para un cliente."""
    plan = PLANS.get(client["plan"], PLANS["free"])
    daily_limit = plan["daily_tokens"]
    usage = get_today_usage(client["id"])
    used = usage["tokens_in"] + usage["tokens_out"]

    return {
        "plan": client["plan"],
        "daily_limit": daily_limit,
        "used_today": used,
        "remaining": max(0, daily_limit - used) if daily_limit != -1 else -1,
        "calls_today": usage["calls"],
    }
