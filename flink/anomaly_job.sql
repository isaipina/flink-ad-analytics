-- ./flink/anomaly_job.sql

-- ## Configuración de Ejecución ##
SET 'execution.runtime-mode' = 'streaming';

-- ## Tabla Fuente (Leer resultados del primer job) ##
-- Lee del tópico donde el primer job escribe los resultados de CTR
CREATE TABLE ctr_results_source (
    window_start TIMESTAMP(3),
    window_end TIMESTAMP(3),
    campaign_id STRING,
    impression_count BIGINT,
    click_count BIGINT,
    ctr DOUBLE,
    -- Usar 'window_end' como el tiempo del evento para procesar esta secuencia de resultados
    event_time AS window_end,
    -- Definir marca de agua para manejar posible retraso en la llegada de resultados
    WATERMARK FOR event_time AS event_time - INTERVAL '10' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'ctr_results', -- Tópico de resultados del primer job
    'properties.bootstrap.servers' = 'kafka:9093',
    'properties.group.id' = 'flink_anomaly_consumer', -- Nuevo group ID
    'format' = 'json',
    'json.ignore-parse-errors' = 'true',
    -- Empezar a leer desde lo último para no procesar historial viejo al reiniciar
    'scan.startup.mode' = 'latest-offset'
);

-- ## Tabla Destino (Escribir alertas de anomalía) ##
CREATE TABLE anomaly_alerts_sink (
    alert_time TIMESTAMP(3),    -- Momento en que se detecta la anomalía (fin de la ventana)
    campaign_id STRING,
    current_ctr DOUBLE,         -- El CTR actual que disparó la alerta
    previous_ctr DOUBLE,        -- El CTR de la ventana anterior para comparación
    alert_type STRING           -- Tipo de alerta: 'SPIKE' o 'DROP'
) WITH (
    'connector' = 'kafka',
    'topic' = 'anomaly_alerts', -- Nuevo tópico para alertas
    'properties.bootstrap.servers' = 'kafka:9093',
    'format' = 'json',
    'sink.partitioner' = 'round-robin'
);

-- ## Lógica de Detección de Anomalías ##

-- Paso 1: Calcular el CTR de la ventana anterior para cada campaña
-- Usamos una vista para mantener la lógica organizada
CREATE VIEW ctr_with_previous AS
SELECT
    event_time, -- Es el window_end de la tabla fuente
    campaign_id,
    ctr AS current_ctr,
    impression_count, -- Mantener para filtrar ruido (opcional)
    -- Obtener el CTR de la fila anterior para la misma campaña, ordenado por tiempo
    LAG(ctr, 1) OVER (PARTITION BY campaign_id ORDER BY event_time) as previous_ctr
FROM ctr_results_source;
-- Opcional: Podrías añadir un WHERE aquí para ignorar ventanas con muy pocas impresiones,
-- por ejemplo: WHERE impression_count > 10

-- Paso 2: Comparar CTR actual con el anterior y generar alertas
INSERT INTO anomaly_alerts_sink
SELECT
    event_time AS alert_time,
    campaign_id,
    current_ctr,
    previous_ctr,
    -- Determinar el tipo de alerta
    CASE
        -- Condición de SPIKE: CTR actual es más del doble del anterior (y anterior no era cero)
        WHEN previous_ctr > 0 AND current_ctr > (previous_ctr * 2.0) THEN 'SPIKE'
        -- Condición de DROP: CTR actual es menos de la mitad del anterior
        WHEN current_ctr < (previous_ctr * 0.5) THEN 'DROP'
        -- Nota: No necesitamos un ELSE NULL porque filtraremos abajo
    END AS alert_type
FROM ctr_with_previous
-- Condiciones para generar una alerta:
WHERE
    previous_ctr IS NOT NULL -- Necesitamos un valor previo para comparar
    AND ( -- Ocurre un SPIKE o un DROP significativo
         (previous_ctr > 0 AND current_ctr > (previous_ctr * 2.0)) -- Condición SPIKE
         OR
         (current_ctr < (previous_ctr * 0.5))                     -- Condición DROP
        );
