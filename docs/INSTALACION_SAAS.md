# Despliegue como complemento SaaS — cuota por organización

Esta modalidad permite ofrecer el chatbot como complemento de una plataforma SaaS,
con un límite de consultas diario por organización cliente.

## Cómo funciona

El chatbot se instala una sola vez en el servidor central de la plataforma.
Todos los clientes acceden al mismo servicio y al mismo índice de documentos
(los manuales de la plataforma). Lo único que varía entre organizaciones
es cuántas consultas pueden hacer al día.

```
Servidor central
├── FAISS index (manuales de la plataforma) — compartido por todos
├── Redis — contador de consultas por organización y día
└── Una sola Groq API key — gestionada internamente

Organización A → 100 consultas/día (plan Standard)
Organización B → 500 consultas/día (plan Premium)
```

## Qué hay que añadir al código actual

El cambio principal es sustituir la `CLIENT_API_KEY` global por una key
única por organización, y añadir un contador Redis que se resetea cada 24 horas.


Cuando una organización supera su límite, la API devuelve `HTTP 429`.
El contador se reinicia automáticamente a las 24 horas.

## Integración con la plataforma

La plataforma incluye el widget del chatbot pasando la API key
de la organización activa. El chatbot se puede incrustar como
iframe o como widget JavaScript en el panel de la plataforma.

## Requisitos adicionales

- **Redis 6+** en el servidor para los contadores de cuota
- Gestión de organizaciones y API keys desde la base de datos de la plataforma

Para la implementación detallada con ejemplos de código completos,
ver el apartado *Despliegue multi-organización* del `README.md`.
