# Asistente Virtual IA — Guía de instalación

Sistema de chatbot inteligente que responde preguntas sobre tus documentos PDF.
Se instala en cualquier servidor Ubuntu y se integra en cualquier web con un solo bloque de código.

---

## Requisitos

| Recurso | Minimo       |
|---------|-------------|
| Sistema | Ubuntu 20.04+ |
| Python  | 3.11+       |
| RAM     | 4 GB        |
| Disco   | 4 GB libres |
| Acceso  | sudo        |

> Si el servidor no tiene Python instalado, ejecuta primero:
> ```bash
> sudo apt update && sudo apt install -y python3 python3-venv python3-pip git
> ```

---

## Paso 1 — Obtener una clave de Groq (gratis)

El chatbot usa Groq como motor de IA. El plan gratuito es suficiente.

1. Entra en **https://console.groq.com** y crea una cuenta
2. Ve a **API Keys** → **Create API Key**
3. Copia la clave (empieza por `gsk_...`) — la necesitarás en el paso 3

---

## Paso 2 — Descargar e instalar

```bash
# Clona el repositorio en la carpeta donde quieras instalarlo
git clone https://github.com/Chupacharcos/chatbot.git
cd chatbot
```

---

## Paso 3 — Colocar tu PDF

Copia el documento que quieres que el chatbot conozca:

```bash
# Español
cp /ruta/a/tu/documento.pdf data/manual_es.pdf

# Inglés (opcional)
cp /ruta/a/tu/documento_en.pdf data/manual_en.pdf
```

> Los nombres de archivo deben seguir el formato `manual_es.pdf`, `manual_en.pdf`, etc.
> Si no tienes el PDF ahora, puedes añadirlo después y procesar manualmente.

---

## Paso 4 — Ejecutar el instalador

```bash
bash setup.sh
```

El instalador hace todo de forma interactiva:

1. **Modo de instalacion:**
   - Elige `1` (Produccion) — el chatbot usa los PDFs que colocaste en `data/`
   - Elige `2` (Desarrollo) — los usuarios suben su PDF desde el navegador

2. **Clave Groq:** pega la clave del paso 1

3. **CLIENT_API_KEY:** clave del cliente principal/demo (se registra automáticamente en el sistema SaaS)

4. **ADMIN_SECRET:** contraseña para el panel de administración SaaS — generada automáticamente si no se indica

4. **Puerto:** acepta el valor por defecto `8088` o cambialo si ya esta ocupado

5. **Acceso via nginx** (recomendado) o **IP directa**:
   - Si tienes dominio con nginx: elige opcion `1` e indica la URL completa
     (p. ej. `https://misitio.com/chatbot-api`)
   - Si no tienes nginx: elige opcion `2`, el chatbot escuchara en `http://IP:8088`

El instalador termina mostrando un resumen con la URL y los comandos utiles.

> La instalacion descarga los modelos de IA (~2 GB). Puede tardar entre 3 y 8 minutos
> segun la velocidad de la conexion del servidor.

---

## Verificar que funciona

```bash
# Estado del servicio
sudo systemctl status chatbot

# Health check
curl http://127.0.0.1:8088/

# Prueba de consulta real
curl -X POST http://127.0.0.1:8088/query \
  -H "Content-Type: application/json" \
  -H "X-API-Key: TU_CLIENT_API_KEY" \
  -d '{"question":"Hola, que puedes hacer?","lang":"es","session_id":""}'
```

Respuesta esperada del health check:
```json
{"status":"ok","message":"Asistente Virtual IA activo","version":"3.0","features":["static_index","dynamic_pdf_upload","saas_multi_tenant"]}
```

---

## Poner el chatbot en tu web

Al terminar el instalador se generan dos archivos:

| Archivo               | Para que sirve                                   |
|-----------------------|--------------------------------------------------|
| `chatbot_widget.html` | Codigo a pegar en tu web                        |
| `chatbot_ejemplo.html`| Pagina de prueba lista para abrir en el navegador|

### Probar antes de integrarlo

Sube `chatbot_ejemplo.html` a tu servidor y abralo en el navegador.
Veras el boton del chatbot en la esquina inferior derecha.

### Integrar en tu web

Abre `chatbot_widget.html`, copia todo su contenido y pegalo justo antes del cierre `</body>`
de la pagina (o del layout principal de tu proyecto):

```html
  <!-- ... tu contenido ... -->

  <!-- PEGA AQUI el contenido de chatbot_widget.html -->

</body>
</html>
```

#### HTML estatico

Abre tu `index.html` y pega el bloque antes de `</body>`.

#### WordPress

En el panel de WordPress: **Apariencia → Editor de temas → footer.php**
Pega el bloque antes de `</body>`.

O en `functions.php`:
```php
add_action('wp_footer', function() {
    include get_template_directory() . '/chatbot_widget.html';
});
```

#### Laravel / Blade

```bash
cp chatbot_widget.html /ruta/proyecto/resources/views/partials/chatbot.blade.php
```

En tu layout principal (`layouts/app.blade.php`) antes de `</body>`:
```blade
@include('partials.chatbot')
```

#### Vue / React / Next.js

Copia el bloque HTML al componente raiz (`App.vue`, `_app.tsx`, `layout.tsx`).
El CSS puedes moverlo a tu hoja de estilos global y el `<script>` al final del mismo componente.

---

## Gestion del servicio

```bash
sudo systemctl status chatbot      # Ver estado
sudo systemctl restart chatbot     # Reiniciar
sudo systemctl stop chatbot        # Parar
sudo systemctl start chatbot       # Arrancar
tail -f logs/api.log               # Ver logs en tiempo real
```

El servicio arranca automaticamente con el servidor (configurado como servicio systemd).

---

## Actualizar el documento PDF

Si cambias el manual y quieres que el chatbot lo conozca:

```bash
# 1. Copia el nuevo PDF
cp /ruta/nuevo-manual.pdf data/manual_es.pdf

# 2. Procesa el PDF (genera el indice de busqueda)
./venv/bin/python3 src/process_manual.py --lang es --pdf data/manual_es.pdf

# 3. Reinicia el servicio
sudo systemctl restart chatbot
```

---

## Solución de problemas

| Problema                        | Comando de diagnostico                         |
|---------------------------------|------------------------------------------------|
| El servicio no arranca          | `sudo journalctl -u chatbot -n 50`            |
| La API no responde              | `tail -f logs/api.log`                         |
| Error 403 / Unauthorized        | Comprueba que `X-API-Key` existe en `/admin/clients` y el cliente está activo |
| El chatbot dice que no sabe     | Los PDFs no estan procesados — ver paso 3      |
| nginx da 502 Bad Gateway        | Comprueba que el servicio esta activo          |

Para cualquier problema, los logs detallados estan en `logs/api.log`.

---

## Referencia rapida de la API

URL base: la que configuraste en `PUBLIC_API_URL` del `.env`

**Endpoints cliente** (auth: `X-API-Key: tu_api_key`):

| Endpoint               | Metodo | Descripcion                      |
|------------------------|--------|----------------------------------|
| `/`                    | GET    | Estado del servidor              |
| `/query`               | POST   | Hacer una pregunta               |
| `/upload`              | POST   | Subir PDF (modo dinamico)        |
| `/stats`               | GET    | Cuota restante hoy               |
| `/docs`                | GET    | Documentacion Swagger            |

**Endpoints admin** (auth: `X-Admin-Secret: tu_admin_secret`):

| Endpoint               | Metodo | Descripcion                      |
|------------------------|--------|----------------------------------|
| `/admin/clients`       | GET    | Listar clientes y cuotas         |
| `/admin/clients`       | POST   | Crear nuevo cliente              |
| `/admin/clients/{id}`  | PATCH  | Cambiar plan o desactivar        |
| `/admin/usage`         | GET    | Informe de uso de tokens         |

Ejemplo de consulta:
```bash
curl -X POST https://misitio.com/chatbot-api/query \
  -H "Content-Type: application/json" \
  -H "X-API-Key: tu_clave" \
  -d '{"question":"Como me registro?","lang":"es","session_id":""}'
```
