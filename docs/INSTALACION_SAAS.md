# Chatbot IA — Guía de administración SaaS

Esta guía cubre la gestión del sistema multi-tenant: crear clientes,
asignar planes, monitorizar uso y controlar cuotas.

**No se necesita Redis ni ninguna dependencia adicional.**
El sistema usa SQLite embebido (`chatbot_saas.db`) que se crea automáticamente al arrancar.

---

## Arquitectura del sistema SaaS

```
Servidor único
├── FastAPI v3.0 (api.py)
├── FAISS indexes (compartidos por todos los clientes)
├── chatbot_saas.db (SQLite)
│   ├── tabla clients   — API keys, planes, estado activo
│   └── tabla usage_log — tokens consumidos por cliente y día
└── .env
    ├── GROQ_API_KEY    — proveedor LLM
    ├── CLIENT_API_KEY  — cliente demo/inicial (auto-registrado)
    └── ADMIN_SECRET    — acceso al panel de administración
```

---

## Planes disponibles

| Plan         | Tokens/día | PDF máximo | Sesiones activas | Descripción                |
|--------------|-----------|------------|-----------------|----------------------------|
| `free`       | 5.000     | 5 MB       | 2               | Demos y pruebas            |
| `basic`      | 50.000    | 20 MB      | 10              | Pequeñas empresas          |
| `pro`        | 500.000   | 50 MB      | 50              | Uso intensivo / agencias   |
| `enterprise` | Ilimitado | 100 MB     | Ilimitadas      | Sin restricciones          |

> Los tokens son la suma de tokens de entrada (prompt) + tokens de salida (respuesta) que
> Groq reporta en cada llamada. Una consulta típica consume entre 500 y 1.500 tokens.

---

## Variables de entorno (.env)

| Variable         | Obligatoria | Descripción                                                       |
|------------------|-------------|-------------------------------------------------------------------|
| `GROQ_API_KEY`   | **Sí**      | Clave API de https://console.groq.com                             |
| `CLIENT_API_KEY` | Recomendada | API key del cliente demo inicial (auto-registrada en SQLite)      |
| `ADMIN_SECRET`   | **Sí**      | Contraseña para `/admin/*` — generar con `openssl rand -hex 24`   |
| `SAAS_DB_PATH`   | No          | Ruta DB SQLite (default: `chatbot_saas.db` en directorio de trabajo) |

---

## Administración por API REST

Todos los endpoints de admin requieren la cabecera:
```
X-Admin-Secret: {valor de ADMIN_SECRET en .env}
```

### Crear un nuevo cliente

```bash
curl -X POST http://127.0.0.1:8088/admin/clients \
  -H "X-Admin-Secret: TU_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"name": "Empresa ABC S.L.", "plan": "basic"}'
```

Respuesta:
```json
{
  "status": "created",
  "client": {
    "id": 2,
    "name": "Empresa ABC S.L.",
    "api_key": "ck_d626d9c55ca51f3d9cc5d13417e04d3b...",
    "plan": "basic",
    "active": 1,
    "created_at": "2026-04-04"
  }
}
```

> Guarda la `api_key` — es la credencial que entregas al cliente. No se puede recuperar después.
> Si la pierdes, crea un cliente nuevo o modifica la DB directamente.

Para crear un cliente con una API key personalizada:
```bash
curl -X POST http://127.0.0.1:8088/admin/clients \
  -H "X-Admin-Secret: TU_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"name": "Empresa ABC S.L.", "plan": "pro", "api_key": "mi-clave-personalizada"}'
```

---

### Listar todos los clientes

```bash
curl http://127.0.0.1:8088/admin/clients \
  -H "X-Admin-Secret: TU_ADMIN_SECRET"
```

Respuesta:
```json
{
  "clients": [
    {
      "id": 1,
      "name": "Demo Portfolio",
      "plan": "pro",
      "active": 1,
      "quota": {
        "daily_limit": 500000,
        "used_today": 1203,
        "remaining": 498797,
        "calls_today": 4
      }
    },
    {
      "id": 2,
      "name": "Empresa ABC S.L.",
      "plan": "basic",
      "active": 1,
      "quota": {
        "daily_limit": 50000,
        "used_today": 0,
        "remaining": 50000,
        "calls_today": 0
      }
    }
  ],
  "plans": { ... }
}
```

---

### Cambiar el plan de un cliente

```bash
# Subir a pro
curl -X PATCH http://127.0.0.1:8088/admin/clients/2 \
  -H "X-Admin-Secret: TU_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"plan": "pro"}'

# Bajar a free
curl -X PATCH http://127.0.0.1:8088/admin/clients/2 \
  -H "X-Admin-Secret: TU_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"plan": "free"}'
```

---

### Desactivar / reactivar un cliente

```bash
# Bloquear acceso sin borrar datos
curl -X PATCH http://127.0.0.1:8088/admin/clients/2 \
  -H "X-Admin-Secret: TU_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"active": false}'

# Reactivar
curl -X PATCH http://127.0.0.1:8088/admin/clients/2 \
  -H "X-Admin-Secret: TU_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"active": true}'
```

Un cliente desactivado recibe HTTP 403 en todas sus llamadas.

---

### Informe de uso de tokens

```bash
# Últimos 7 días (por defecto)
curl "http://127.0.0.1:8088/admin/usage" \
  -H "X-Admin-Secret: TU_ADMIN_SECRET"

# Últimos 30 días
curl "http://127.0.0.1:8088/admin/usage?days=30" \
  -H "X-Admin-Secret: TU_ADMIN_SECRET"
```

Respuesta:
```json
{
  "days": 7,
  "usage": [
    {
      "id": 1, "name": "Demo Portfolio", "plan": "pro",
      "log_date": "2026-04-04",
      "tokens_in": 343, "tokens_out": 360, "calls": 1
    }
  ]
}
```

---

### Ver planes disponibles

```bash
curl http://127.0.0.1:8088/admin/plans \
  -H "X-Admin-Secret: TU_ADMIN_SECRET"
```

---

## Lo que ve el cliente

El cliente solo necesita su `api_key`. Puede consultar su cuota en cualquier momento:

```bash
curl http://IP:PUERTO/stats -H "X-API-Key: ck_abc123..."
```

```json
{
  "client": "Empresa ABC S.L.",
  "plan": "basic",
  "sesiones_activas": 1,
  "mensajes_totales": 12,
  "quota": {
    "daily_limit": 50000,
    "used_today": 4200,
    "remaining": 45800,
    "calls_today": 8
  }
}
```

Si supera la cuota, recibe:
```
HTTP 429 — "Cuota diaria agotada (50000/50000 tokens). Se renueva a las 00:00 UTC."
```

---

## Gestión directa de la base de datos SQLite

Para operaciones avanzadas (backup, auditoría, migración de clientes):

```bash
# Ubicación por defecto
sqlite3 /var/www/chatbot/chatbot_saas.db

# Ver todos los clientes
SELECT id, name, plan, active, created_at FROM clients;

# Ver uso del mes actual
SELECT c.name, u.log_date, u.tokens_in + u.tokens_out AS total_tokens, u.calls
FROM usage_log u JOIN clients c ON c.id = u.client_id
WHERE u.log_date >= date('now', 'start of month')
ORDER BY u.log_date DESC;

# Backup
cp /var/www/chatbot/chatbot_saas.db /backups/chatbot_saas_$(date +%Y%m%d).db
```

---

## Recomendaciones de operación

- **Backup diario** de `chatbot_saas.db` — contiene toda la información de clientes y cuotas
- **No versionar** `chatbot_saas.db` en git — ya está en `.gitignore`
- **Rotar `ADMIN_SECRET`** periódicamente si se comparte con terceros
- La cuota se reinicia automáticamente cada día a las 00:00 UTC — no se necesita ningún cron
