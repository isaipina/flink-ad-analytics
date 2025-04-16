# Real-Time Ad Click Analytics Pipeline with Flink (Take-Home Test)

Este proyecto implementa un pipeline de análisis en tiempo real utilizando Apache Flink para procesar eventos simulados de impresiones y clics de anuncios. El sistema calcula métricas de CTR por campaña, engagement por dispositivo, detecta anomalías de CTR y visualiza los resultados en un dashboard, todo orquestado mediante Docker Compose.

## Features Implementadas

* **Pipeline Principal:** Lee streams de impresiones y clics desde Kafka, realiza un join basado en tiempo, calcula agregaciones en ventanas de 1 minuto (CTR por campaña, conteos por dispositivo) y escribe los resultados en tópicos de Kafka (`ctr_results`, `engagement_results`).
* **Detección de Anomalías (Bonus):** Un segundo job Flink lee los resultados de CTR, compara el CTR actual con el de la ventana anterior para cada campaña, y envía alertas (`SPIKE`/`DROP`) a un tópico Kafka (`anomaly_alerts`) si se superan umbrales predefinidos.
* **Generador de Datos Controlado:** Simula eventos de impresiones y clics. Se ha modificado para:
    * Limitar el CTR máximo simulado (evitando el 100% constante).
    * Introducir fases de comportamiento predecibles (CTR normal, bajo, alto) para una campaña específica (`camp-1`) para facilitar la prueba de la detección de anomalías.
* **Dashboard de Visualización (Bonus):** Una aplicación Streamlit que consume y muestra en tiempo real los resultados de CTR, Engagement y Alertas de Anomalía desde Kafka.
* **Entorno Dockerizado:** Toda la pila (Kafka, Zookeeper, Flink, Generador de Datos, Dashboard) se gestiona con Docker Compose.

## Tech Stack

* Docker & Docker Compose
* Apache Kafka 3.4 (Imagen Bitnami)
* Apache Flink 1.17 (SQL API)
* Python 3.9 (Generador de Datos, Dashboard)
* Streamlit
* kafka-python, Pandas

## Estructura del Proyecto
    .
    ├── docker-compose.yml      # Define todos los servicios Docker
    ├── flink/
    │   ├── flink_job.sql       # Job Flink SQL principal (CTR/Engagement) - Usa COUNT(DISTINCT)
    │   └── anomaly_job.sql     # Job Flink SQL secundario (Detección Anomalías)
    ├── flink-jars/
    │   └── flink-sql-connector-kafka-1.17.2.jar # Conector Kafka (Requiere descarga manual)
    ├── data-generator/
    │   ├── Dockerfile
    │   ├── generate_events.py  # Script generador de datos (con fases controladas)
    │   └── requirements.txt
    ├── dashboard/
    │   ├── Dockerfile
    │   ├── streamlit_app.py    # Script dashboard Streamlit
    │   └── requirements.txt
    ├── .gitignore              # Ignora flink-jars/, pycache, etc.
    └── README.md               

## Prerrequisitos del Evaluador

* Git instalado localmente.
* Docker Desktop instalado y corriendo (con Docker Compose v2+).
* (Si usa WSL 2 en Windows) Integración WSL activada en Docker Desktop para la distribución usada.
* Conexión a Internet (para descargar imágenes Docker y el JAR de Flink).

## Cómo Ejecutar Localmente (Paso a Paso para el Evaluador)

1.  **Clonar el Repositorio:**
    ```bash
    git clone https://github.com/isaipina/flink-ad-analytics
    cd flink-ad-analytics
    ```

2.  **Descargar Conector Flink-Kafka:** (Paso Manual Obligatorio)
    * Descarga el JAR desde: [https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-kafka/1.17.2/flink-sql-connector-kafka-1.17.2.jar]
    * Crea una carpeta llamada `flink-jars` en la raíz del proyecto (si no existe).
    * Coloca el archivo `.jar` descargado dentro de la carpeta `flink-jars/`.

3.  **Construir Imágenes Docker:**
    * Abre una terminal en la raíz del proyecto.
    * Ejecuta:
        ```bash
        docker-compose build
        ```
    * *(Nota: Si se encuentran problemas con código Python no actualizado, se puede forzar una reconstrucción sin caché con `docker-compose build --no-cache data-generator dashboard`)*

4.  **Iniciar Todo el Entorno:**
    ```bash
    docker-compose up -d
    ```
    * Espera ~1-2 minutos para que todos los servicios se inicien (Kafka necesita un tiempo, Flink depende de Kafka).

5.  **Enviar los Jobs de Flink al Cluster:**
    * Asegúrate de que los contenedores estén corriendo (`docker-compose ps`).
    * **Enviar Job Principal (CTR/Engagement):**
        ```bash
        docker-compose exec jobmanager /opt/flink/bin/sql-client.sh -f /opt/flink/usrlib/flink_job.sql
        ```
    * **Enviar Job de Anomalías:** (Espera unos segundos tras enviar el primero)
        ```bash
        docker-compose exec jobmanager /opt/flink/bin/sql-client.sh -f /opt/flink/usrlib/anomaly_job.sql
        ```

## Cómo Validar el Funcionamiento

1.  **Estado de los Contenedores:**
    * Ejecuta `docker-compose ps`.
    * **Verifica:** Todos los servicios (`zookeeper`, `kafka`, `jobmanager`, `taskmanager`, `data-generator`, `dashboard`) deben mostrar estado `Up`. `kafka-setup` debe mostrar `Exit 0`.

2.  **Estado de los Jobs Flink:**
    * Accede a la Flink UI: [http://localhost:8081](http://localhost:8081)
    * **Verifica:** Deberías ver **2** jobs en estado `RUNNING`. Puedes hacer clic en ellos para ver el grafo y las métricas. *(Nota: Las métricas de la UI, especialmente contadores de entrada/salida, pueden tener retraso)*.

3.  **Funcionamiento del Generador de Datos:**
    * Ejecuta `docker-compose logs -f data-generator`. El flag `-f` sigue mostrando logs en tiempo real (Usa `Ctrl+C` para salir).


4.  **Dashboard Streamlit:**
    * Accede al Dashboard: [http://localhost:8501](http://localhost:8501)
    * Espera ~1 minuto para que cargue datos iniciales.
    * **Verifica:**
        * ¿Se muestran datos en las tablas y gráficas de CTR y Engagement?
        * ¿Se actualizan los datos periódicamente?

5.  **Salida Directa de Kafka (Validación Detallada):**
    * Usa los consumidores de consola en terminales separadas:
    * **`ctr_results`:**
        ```bash
        docker-compose exec kafka kafka-console-consumer.sh --bootstrap-server kafka:9093 --topic ctr_results --from-beginning
        ```
    * **`engagement_results`:**
        ```bash
        docker-compose exec kafka kafka-console-consumer.sh --bootstrap-server kafka:9093 --topic engagement_results --from-beginning
        ```
    * **`anomaly_alerts`:**
        ```bash
        docker-compose exec kafka kafka-console-consumer.sh --bootstrap-server kafka:9093 --topic anomaly_alerts --from-beginning
        ```

## Notas Importantes y Troubleshooting (Historial de Desarrollo)

* **Conector Flink-Kafka:** Es **obligatorio** descargarlo manualmente y colocarlo en `flink-jars/` antes de ejecutar `docker-compose up`.
* **Comportamiento del JOIN (`LEFT JOIN` vs `INNER JOIN`):** Durante el desarrollo, se observó persistentemente que al usar `LEFT JOIN` con `COUNT(columna)` o `COUNT(*)`, los resultados mostraban `impression_count == click_count` (CTR=1.0), lo cual es incorrecto según la lógica del generador de datos. Esto sugiere un comportamiento inesperado en cómo Flink SQL 1.17 maneja esta combinación específica de `LEFT INTERVAL JOIN` y agregación en ventana. La versión actual de `flink_job.sql` usa **`COUNT(DISTINCT ...)`** como la mejor alternativa encontrada dentro de SQL para intentar obtener conteos correctos (`impression_count >= click_count`). Se recomienda al evaluador verificar si los resultados numéricos con esta versión son los esperados (CTR < 1.0).
* **Generador de Datos (`generate_events.py`):** La versión actual produce un CTR limitado (`MAX_CTR_CAP`) e introduce fases predecibles de CTR bajo/alto para `camp-1` para poder probar la detección de anomalías. Incluye reintentos al conectar con Kafka.
* **Infraestructura Docker:** Se ajustó `kafka-setup` para usar `sleep`. Se corrigieron problemas iniciales de conexión del `data-generator`. Se requiere `--build` (y a veces `--no-cache`) si se modifica código Python.
* **UI Flink:** Las métricas mostradas pueden no ser 100% en tiempo real. Validar preferentemente con la salida de Kafka o el Dashboard.

## Detener el Entorno

Para detener todos los contenedores y opcionalmente eliminar los volúmenes:

```bash
# Detener y eliminar contenedores, redes Y VOLÚMENES
docker-compose down -v
