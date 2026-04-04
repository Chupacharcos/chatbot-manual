# Asistente Virtual IA sobre Documentos
## Propuesta Comercial

---

## ¿Qué problema resuelve?

Sus empleados y clientes pierden tiempo buscando información en manuales de decenas o cientos de páginas. Las soluciones actuales (buscadores internos, FAQs estáticas, chatbots genéricos) no leen el documento real, por lo que dan respuestas imprecisas o inexistentes.

**Este sistema convierte cualquier PDF en un asistente que responde preguntas en lenguaje natural, citando siempre la sección exacta del documento.**

---

## Cómo funciona

```
[Su documento PDF]  →  [Indexación semántica]  →  [Asistente disponible]
  Manual de usuario       FAISS + embeddings         en su web, en minutos
  Normativa interna       multilingues (e5-large)
  Contrato / póliza       Cross-Encoder reranking
  Catálogo de producto
```

1. **Sube el PDF** desde el navegador o lo procesamos nosotros
2. **El sistema lo indexa** en 1-3 minutos según el tamaño
3. **El asistente responde** preguntas en el idioma del usuario, con referencias a la página exacta

---

## ¿Por qué no alucina?

A diferencia de ChatGPT y otros chatbots generales, este sistema solo responde con información de **su propio documento**. El proceso de recuperación (RAG) garantiza que cada respuesta parte de fragmentos reales del PDF, no de conocimiento general del modelo.

Si la información no está en el documento, el asistente lo dice.

---

## Características técnicas clave

| Capacidad                  | Detalle                                                             |
|----------------------------|---------------------------------------------------------------------|
| Búsqueda semántica         | Encuentra información aunque el usuario no use las palabras exactas |
| Búsqueda por palabras clave | Complementa la semántica para capturar términos técnicos concretos  |
| Multiidioma                | Responde en el idioma del usuario sin configuración adicional        |
| Historial de conversación  | Recuerda el contexto de los últimos mensajes de la sesión           |
| Personalidad configurable  | Tono, sector y restricciones de respuesta definibles por cliente    |
| PDF hasta 100 MB           | Documentos de cualquier tamaño (límite según plan)                  |
| Respuesta < 3 segundos     | Retrieval + reranking + LLM en menos de 3 segundos de media         |
| Fuentes citadas            | Cada respuesta indica la sección y página de origen                 |

---

## Modalidades de despliegue

### A. Instalación en su servidor (licencia perpetua)

El sistema se instala en su infraestructura (servidor propio o VPS). Sus datos nunca salen de su entorno.

**Incluye:**
- Código fuente completo
- Script de instalación automatizado (`setup.sh`)
- Guía de integración para web, WordPress, Laravel, React, etc.
- Widget JavaScript listo para pegar en cualquier página
- 3 meses de soporte técnico por email

**Requisitos del servidor:**
- Ubuntu 20.04+ · 4 GB RAM · 5 GB disco · Python 3.11+
- Sin necesidad de GPU · Sin Redis · Sin bases de datos externas

---

### B. Servicio gestionado SaaS (suscripción mensual)

Nosotros alojamos y mantenemos el servicio. Usted solo se integra con su API key.

| Plan         | Tokens/día | PDF máximo | Precio orientativo |
|--------------|-----------|------------|-------------------|
| **Free**     | 5.000     | 5 MB       | 0 €/mes (demo)    |
| **Basic**    | 50.000    | 20 MB      | Consultar         |
| **Pro**      | 500.000   | 50 MB      | Consultar         |
| **Enterprise**| Ilimitado | 100 MB    | Consultar         |

> **¿Cuántos tokens necesito?** Una consulta típica consume entre 500 y 1.500 tokens.
> El plan Basic (50.000 tokens/día) soporta entre 33 y 100 consultas diarias.

**El medidor se reinicia automáticamente cada día a las 00:00 UTC.**

**Incluye:**
- Endpoint `/stats` para que el cliente consulte su cuota restante en tiempo real
- HTTP 429 automático al superar la cuota (sin cargos extra)
- Panel de administración REST para crear, modificar y desactivar clientes
- Informe de uso de tokens por cliente y por día

---

## Comparativa con soluciones existentes

| Solución                   | Coste mensual           | Sus datos         | Personalización     |
|----------------------------|------------------------|-------------------|---------------------|
| **Esta solución (SaaS)**   | Desde 0 € (demo)       | ✅ Su infraestructura | ✅ Total           |
| **Esta solución (licencia)**| Pago único             | ✅ Su servidor    | ✅ Código fuente    |
| Intercom Fin AI            | 390 €+ · 0,99 €/conv.  | ⚠️ Sus servidores | ⚠️ Limitada        |
| Zendesk AI Agents          | 250–600 €              | ⚠️ Sus servidores | ⚠️ Limitada        |
| ChatGPT Enterprise         | 3.750 € (mín. 150 users)| ⚠️ OpenAI infra  | ❌ Muy limitada    |
| Notion AI / Confluence AI  | 10–20 € / usuario/mes  | ⚠️ Su app         | ❌ Ninguna         |

**Diferencia clave:** las soluciones de mercado facturan por usuario, por conversación o por seat. Esta solución factura por tokens consumidos. Para equipos medianos o grandes, el ahorro es significativo.

**Ejemplo:** 20 empleados que hacen 10 consultas al día cada uno:
- Intercom Fin AI: 390 € base + 200 consultas × 0,99 € = ~588 €/mes
- Esta solución: ~1,50 €/mes en tokens Groq (a precios actuales)

---

## Integración en su plataforma

Una línea por entorno:

**HTML estático / WordPress:**
```html
<!-- Pegar antes de </body> -->
<!-- El archivo chatbot_widget.html se genera automáticamente tras la instalación -->
```

**JavaScript / fetch:**
```javascript
const respuesta = await fetch('https://su-servidor/query', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', 'X-API-Key': 'su_api_key' },
  body: JSON.stringify({ question: pregunta, session_id: sessionId })
});
const { answer, sources, session_id } = await respuesta.json();
```

**Laravel / Blade:**
```blade
@include('partials.chatbot')
```

**React / Next.js / Vue:** el bloque HTML se copia al componente raíz.

---

## Casos de uso

- **Manuales de software**: el usuario pregunta "¿cómo exporto un informe?" y recibe la respuesta con número de página
- **Normativa interna**: RRHH sube el reglamento de empresa; los empleados consultan sin abrir el PDF
- **Contratos y pólizas**: el cliente pregunta sus condiciones; el asistente responde citando la cláusula exacta
- **Catálogos de producto**: el comercial pregunta especificaciones técnicas durante una llamada
- **Atención al cliente**: reduce el volumen de tickets de soporte para preguntas ya documentadas
- **Formación**: los empleados en onboarding consultan el manual a su ritmo, sin saturar al equipo de RRHH

---

## Seguridad y privacidad

- Los PDF procesados **nunca salen del servidor** donde está instalado el sistema
- Solo el fragmento relevante (unos pocos párrafos) llega al proveedor LLM (Groq)
- Cada cliente tiene su propia API key — sin acceso cruzado entre cuentas
- El historial de conversación es efímero (en RAM) y se elimina tras 4 horas de inactividad
- Sin almacenamiento de conversaciones en disco

---

## Próximos pasos

1. **Demo gratuita**: probamos el sistema con un PDF suyo en menos de 10 minutos
2. **Propuesta personalizada**: según número de usuarios, volumen de consultas y modo de despliegue
3. **Instalación**: 1-2 horas en servidor existente o nuevo VPS

---

*Propuesta generada por Adrian Moreno — adrianmoreno-dev.com*
*Contacto: [adrian@adrianmoreno-dev.com](mailto:adrian@adrianmoreno-dev.com)*
