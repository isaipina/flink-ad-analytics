--  Configuración de Ejecución 
SET 'execution.runtime-mode' = 'streaming';

--  Definición de Tablas Origen (Kafka) 
CREATE TABLE impressions (
    impression_id STRING,
    user_id STRING,
    campaign_id STRING,
    ad_id STRING,
    device_type STRING,
    browser STRING,
    event_timestamp BIGINT,
    cost DECIMAL(10, 2),
    event_time AS TO_TIMESTAMP_LTZ(event_timestamp, 3),
    WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'ad-impressions',
    'properties.bootstrap.servers' = 'kafka:9093',
    'properties.group.id' = 'flink_impression_consumer_distinct', -- Cambiar group.id por si acaso
    'format' = 'json',
    'json.ignore-parse-errors' = 'true',
    'scan.startup.mode' = 'earliest-offset'
);

CREATE TABLE clicks (
    click_id STRING,
    impression_id STRING,
    user_id STRING,
    event_timestamp BIGINT,
    event_time AS TO_TIMESTAMP_LTZ(event_timestamp, 3),
    WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'ad-clicks',
    'properties.bootstrap.servers' = 'kafka:9093',
    'properties.group.id' = 'flink_click_consumer_distinct', -- Cambiar group.id por si acaso
    'format' = 'json',
    'json.ignore-parse-errors' = 'true',
    'scan.startup.mode' = 'earliest-offset'
);

-- Definición de Tablas Destino (Kafka) 
CREATE TABLE ctr_results_sink (
    window_start TIMESTAMP(3),
    window_end TIMESTAMP(3),
    campaign_id STRING,
    impression_count BIGINT, 
    click_count BIGINT,      
    ctr DOUBLE
) WITH (
    'connector' = 'kafka',
    'topic' = 'ctr_results',
    'properties.bootstrap.servers' = 'kafka:9093',
    'format' = 'json',
    'sink.partitioner' = 'round-robin'
);

CREATE TABLE engagement_results_sink (
    window_start TIMESTAMP(3),
    window_end TIMESTAMP(3),
    device_type STRING,
    impression_count BIGINT, 
    click_count BIGINT      
) WITH (
    'connector' = 'kafka',
    'topic' = 'engagement_results',
    'properties.bootstrap.servers' = 'kafka:9093',
    'format' = 'json',
    'sink.partitioner' = 'round-robin'
);

-- Lógica de Procesamiento y Inserción 
BEGIN STATEMENT SET;

-- Calculo de CTR por Campaña en ventanas de 1 minuto (usando COUNT DISTINCT)
INSERT INTO ctr_results_sink
SELECT
    TUMBLE_START(i.event_time, INTERVAL '1' MINUTE) as window_start,
    TUMBLE_END(i.event_time, INTERVAL '1' MINUTE) as window_end,
    i.campaign_id,
    -- Contar impresiones únicas en el grupo
    COUNT(DISTINCT i.impression_id) as impression_count,
    -- Contar clics únicos (asociados) en el grupo
    COUNT(DISTINCT c.click_id) as click_count,
    -- Calcular CTR
    CASE
        WHEN COUNT(DISTINCT i.impression_id) > 0 THEN CAST(COUNT(DISTINCT c.click_id) AS DOUBLE) / COUNT(DISTINCT i.impression_id)
        ELSE 0.0
    END as ctr
FROM
    impressions i
LEFT JOIN
    clicks c ON i.impression_id = c.impression_id
    AND c.event_time BETWEEN i.event_time AND i.event_time + INTERVAL '10' MINUTE
GROUP BY
    TUMBLE(i.event_time, INTERVAL '1' MINUTE),
    i.campaign_id;


-- Calculo de Engagement por Tipo de Dispositivo en ventanas de 1 minuto (usando COUNT DISTINCT)
INSERT INTO engagement_results_sink
SELECT
    TUMBLE_START(i.event_time, INTERVAL '1' MINUTE) as window_start,
    TUMBLE_END(i.event_time, INTERVAL '1' MINUTE) as window_end,
    COALESCE(i.device_type, 'Unknown') as device_type,
    -- Contar impresiones únicas en el grupo
    COUNT(DISTINCT i.impression_id) as impression_count,
    -- Contar clics únicos (asociados) en el grupo
    COUNT(DISTINCT c.click_id) as click_count
FROM
    impressions i
LEFT JOIN
    clicks c ON i.impression_id = c.impression_id
    AND c.event_time BETWEEN i.event_time AND i.event_time + INTERVAL '10' MINUTE
GROUP BY
    TUMBLE(i.event_time, INTERVAL '1' MINUTE),
    i.device_type;

END; 