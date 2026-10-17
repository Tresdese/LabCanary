# Laboratorio Canary Release

**Alumno:** Darlington Diego Delgado Santiago  
**Experiencia educativa:** Desarrollo de Sistemas en Red  
**Docente:** Saúl Domínguez Isidro  
**Institución:** Universidad Veracruzana, Facultad de Estadística e Informática

## Objetivo

Implementar un despliegue Canary con Docker Compose y Nginx, distribuir progresivamente el tráfico entre dos versiones de una API y comprobar la recuperación mediante rollback ante un fallo funcional.

## Arquitectura

El entorno se ejecuta dentro de una VM Ubuntu administrada con Vagrant.

| Servicio | Función |
|---|---|
| Blue | Ejecuta la versión v1 de la API. |
| Green | Ejecuta la versión v2 de la API. |
| Proxy | Distribuye las solicitudes mediante Nginx y publica el puerto 8080. |

Blue y Green escuchan en el puerto 3000 dentro de la red de Docker. Solo el proxy publica un puerto hacia la VM.

La API dispone de estas rutas:

- `/health`: comprobación básica de salud.
- `/api/info`: identificación de la versión.
- `/api/checkout`: operación ficticia de compra.

## Requisitos

- VM Ubuntu con Docker Engine y Docker Compose.
- Git, Bash y curl.
- Acceso a Internet para descargar y construir las imágenes.
- Puerto 8080 disponible.
- Para acceder desde el navegador del equipo principal, reenvío del puerto 8080 mediante Vagrant.

Todos los comandos siguientes se ejecutan dentro de la VM, desde la raíz del proyecto.

## Preparación

```bash
git clone https://github.com/TU_USUARIO/laboratorio-canary.git
cd laboratorio-canary

cp .env.example .env
chmod +x scripts/*.sh
mkdir -p evidencias
set -o pipefail

docker compose up -d --build
docker compose ps
```

Cuando los servicios estén listos:

```bash
curl -sS http://127.0.0.1:8080/api/info
```

La configuración inicial debe dirigir el tráfico a Blue y devolver `"version":"v1"`.

## Etapas del despliegue

Después de cada promoción se deja un breve intervalo antes de medir para permitir que Nginx aplique la recarga.

### 1. Blue al 100 %

```bash
./scripts/promote.sh blue
sleep 2
./scripts/sample.sh 100 | tee evidencias/01-blue.txt
```

Verificación interna de Green:

```bash
docker compose exec -T proxy wget -qO- http://green:3000/api/info
```

Green puede responder internamente sin recibir tráfico público.

### 2. Canary al 10 %

```bash
./scripts/promote.sh canary10
sleep 2
./scripts/sample.sh 100 | tee evidencias/02-canary10.txt
./scripts/check-checkout.sh 50 | tee evidencias/02-checkout-sin-fallo.txt
```

Nginx utiliza pesos 9:1 para Blue y Green. Estos pesos distribuyen solicitudes; no asignan permanentemente un grupo de usuarios a cada versión.

### 3. Canary al 50 %

```bash
./scripts/promote.sh canary50
sleep 2
./scripts/sample.sh 100 | tee evidencias/03-canary50.txt
./scripts/check-checkout.sh 50 | tee evidencias/03-checkout.txt
```

### 4. Green al 100 %

```bash
./scripts/promote.sh green
sleep 2
./scripts/sample.sh 30 | tee evidencias/04-green.txt
./scripts/check-checkout.sh 30 | tee evidencias/04-checkout.txt
```

## Resultados observados

| Etapa | Solicitudes a `/api/info` | Blue: v1 | Green: v2 |
|---|---:|---:|---:|
| Blue al 100 % | 100 | 100 | 0 |
| Canary al 10 % | 100 | 90 | 10 |
| Canary al 50 % | 100 | 51 | 49 |
| Green al 100 % | 30 | 0 | 30 |

En las comprobaciones de checkout sin fallo se obtuvieron 50 respuestas HTTP 200 en Canary al 10 %, 50 en Canary al 50 % y 30 en Green al 100 %.

Los valores corresponden a las muestras observadas. Las distribuciones parciales pueden variar entre ejecuciones.

## Incidente simulado

Primero se devuelve el tráfico a Blue y se recrea Green con el fallo habilitado:

```bash
./scripts/promote.sh blue
sleep 2
GREEN_FAIL=true docker compose up -d --force-recreate green
```

Se verifica la variable:

```bash
docker compose exec -T green printenv SIMULATE_ERROR
```

Cuando Green esté lista, se comprueban directamente sus rutas:

```bash
docker compose exec -T green node -e '
(async () => {
  for (const path of ["/health", "/api/checkout"]) {
    const r = await fetch("http://127.0.0.1:3000" + path);
    console.log(path, "HTTP", r.status, await r.text());
  }
})().catch(e => { console.error(e); process.exit(1); });
' | tee evidencias/05-green-fallo.txt
```

Con el fallo habilitado, `/health` devuelve HTTP 200, mientras que `/api/checkout` devuelve HTTP 503.

Se expone Green mediante Canary y se mide el incidente:

```bash
./scripts/promote.sh canary10
sleep 2
./scripts/check-checkout.sh 50 | tee evidencias/06-incidente.txt
```

Se observaron 45 respuestas HTTP 200 y 5 respuestas HTTP 503. El 10 % de errores de la muestra justificó detener la promoción.

## Rollback

```bash
./scripts/promote.sh blue
sleep 2
./scripts/check-checkout.sh 20 | tee evidencias/07-rollback.txt
./scripts/sample.sh 20 | tee evidencias/07-version-rollback.txt
```

Después del rollback se obtuvieron 20 respuestas HTTP 200 y 20 respuestas de v1.

| Prueba de checkout | Solicitudes | HTTP 200 | HTTP 503 |
|---|---:|---:|---:|
| Canary con fallo | 50 | 45 | 5 |
| Después del rollback | 20 | 20 | 0 |

Para restaurar Green sin volver a exponerla:

```bash
GREEN_FAIL=false docker compose up -d --force-recreate green
```

Cuando esté lista:

```bash
docker compose exec -T proxy wget -qO- http://green:3000/api/checkout
```

## GitHub Actions

El archivo `.github/workflows/canary-ci.yml` ejecuta:

1. Descarga del código y preparación de Node.js 22.
2. Pruebas unitarias.
3. Construcción de imágenes e inicio de Compose.
4. Espera de disponibilidad HTTP.
5. Activación de Canary y comprobación de presencia de v1 y v2.
6. Promoción a Green y rollback a Blue.
7. Consulta de registros si ocurre un fallo y limpieza del entorno.

La ejecución se consulta en la pestaña **Actions** del repositorio. El workflow valida el laboratorio en un runner temporal; no despliega automáticamente a la VM Vagrant.

La presencia de ambas versiones no demuestra una proporción exacta de tráfico. El workflow tampoco sustituye las pruebas funcionales del incidente.

## Evidencias

Las salidas de las pruebas se encuentran en la carpeta [evidencias](evidencias/).

La reflexión técnica se encuentra en [REFLEXION.md](REFLEXION.md).

Las capturas documentan el inicio de los servicios, las distribuciones, el fallo funcional y el rollback. La evidencia de GitHub Actions debe corresponder a una ejecución real del repositorio.

## Diagnóstico y cierre

```bash
docker compose ps
docker compose logs --tail=50 proxy blue green
docker compose exec -T proxy nginx -t
```

Para detener y retirar los contenedores del laboratorio:

```bash
docker compose down
```

## Fuente del proyecto

Código base proporcionado para la asignatura:

https://github.com/sdominguez/deployment-strategies/tree/master/demo_canary/canary_lab

No se incluyen credenciales, llaves privadas ni el archivo `.env` en el repositorio.
