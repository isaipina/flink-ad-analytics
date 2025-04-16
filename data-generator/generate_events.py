#!/usr/bin/env python3

import json
import os
import random
import time
import uuid
from datetime import datetime
from typing import Dict, List, Any, Optional

from kafka import KafkaProducer
from kafka.errors import NoBrokersAvailable

# Configuration from environment variables
KAFKA_BROKER = os.environ.get("KAFKA_BROKER", "kafka:9092")
IMPRESSION_TOPIC = os.environ.get("IMPRESSION_TOPIC", "ad-impressions")
CLICK_TOPIC = os.environ.get("CLICK_TOPIC", "ad-clicks")
EVENT_RATE = int(os.environ.get("EVENT_RATE", "50"))  # Events per second
CLICK_RATIO = float(os.environ.get("CLICK_RATIO", "0.1"))  # Base % of impressions that get clicked

# *** NUEVO: Límite máximo para el CTR simulado ***
MAX_CTR_CAP = 0.6 # No permitir que la probabilidad de clic supere el 60%

# Sample data for generation
CAMPAIGNS = [f"camp-{i}" for i in range(1, 11)]
ADS = [f"ad-{i}" for i in range(1, 101)]
DEVICE_TYPES = ["mobile", "desktop", "tablet"]
BROWSERS = ["chrome", "safari", "firefox", "edge"]
USER_POOL_SIZE = 10000

# *** NUEVO: Campaña objetivo para anomalías controladas ***
TARGET_ANOMALY_CAMPAIGN = CAMPAIGNS[0] # Vamos a afectar a 'camp-1'

# Store impressions temporarily to generate clicks (sin cambios)
# impression_buffer: List[Dict[str, Any]] = [] # No estamos usando el buffer en esta versión
# MAX_BUFFER_SIZE = 1000

def create_kafka_producer() -> KafkaProducer:
    """Creates and returns a Kafka producer with retry logic"""
    retries = 5
    delay = 5 # segundos
    attempt = 0
    while attempt < retries:
        try:
            print(f"Attempting to connect to Kafka ({attempt + 1}/{retries})...")
            producer = KafkaProducer(
                bootstrap_servers=KAFKA_BROKER,
                value_serializer=lambda v: json.dumps(v).encode('utf-8'),
                key_serializer=lambda v: v.encode('utf-8') if v else None,
                api_version_auto_timeout_ms=5000
            )
            print("Successfully connected to Kafka.")
            return producer
        except NoBrokersAvailable:
            print(f"No brokers available. Retrying in {delay} seconds...")
            attempt += 1
            if attempt < retries:
                time.sleep(delay)
            else:
                print("Could not connect to Kafka after multiple retries.")
                raise
        except Exception as e:
            print(f"An unexpected error occurred while connecting to Kafka: {e}")
            raise


def generate_impression() -> Dict[str, Any]:
    """Generates a random ad impression event (sin cambios)"""
    user_id = f"user-{random.randint(1, USER_POOL_SIZE)}"
    campaign_id = random.choice(CAMPAIGNS)
    ad_id = random.choice(ADS)
    device_type = random.choice(DEVICE_TYPES)
    browser = random.choice(BROWSERS)
    cost = round(random.uniform(0.01, 0.5), 2)
    timestamp = int(datetime.now().timestamp() * 1000)  # milliseconds

    return {
        "impression_id": str(uuid.uuid4()),
        "user_id": user_id,
        "campaign_id": campaign_id,
        "ad_id": ad_id,
        "device_type": device_type,
        "browser": browser,
        "event_timestamp": timestamp,
        "cost": cost
    }

# Se elimina generate_click ya que la lógica está ahora dentro de main

def main():
    """Main loop to generate and send events with controlled anomalies"""
    producer = create_kafka_producer()

    # No necesitamos el sleep aquí ya que create_kafka_producer tiene reintentos
    print("Starting event generation with controlled anomalies...")

    # Inicializar boosts de campaña
    campaign_click_boost = {campaign: 1.0 for campaign in CAMPAIGNS} # Empezar todos con boost 1.0

    start_time = time.time()
    last_phase_change_logged = -1 # Para loguear cambios de fase solo una vez

    try:
        while True:
            current_time = time.time()
            elapsed_seconds = current_time - start_time

            # *** Lógica de Fases para Anomalías Controladas en TARGET_ANOMALY_CAMPAIGN ***
            current_phase = 0
            if elapsed_seconds < 300: # Fase 1: Baseline (0-5 mins)
                phase = 1
                campaign_click_boost[TARGET_ANOMALY_CAMPAIGN] = 1.0 # Boost Normal
            elif elapsed_seconds < 600: # Fase 2: Drop de CTR (5-10 mins)
                phase = 2
                campaign_click_boost[TARGET_ANOMALY_CAMPAIGN] = 0.1 # Boost Muy Bajo -> DROP
            elif elapsed_seconds < 900: # Fase 3: Spike de CTR (10-15 mins)
                phase = 3
                campaign_click_boost[TARGET_ANOMALY_CAMPAIGN] = 4.0 # Boost Alto -> SPIKE (respetando MAX_CTR_CAP)
            else: # Fase 4: Vuelta a Baseline (>15 mins)
                phase = 4
                campaign_click_boost[TARGET_ANOMALY_CAMPAIGN] = 1.0 # Boost Normal de nuevo

            # Loguear cambio de fase solo una vez
            if phase != last_phase_change_logged:
                 print(f"--- Entering Phase {phase} at {elapsed_seconds:.0f}s ---")
                 print(f"Target campaign '{TARGET_ANOMALY_CAMPAIGN}' boost set to: {campaign_click_boost[TARGET_ANOMALY_CAMPAIGN]}")
                 last_phase_change_logged = phase


            # --- Generación y envío ---
            # Generate impression
            impression = generate_impression()

            # Apply campaign-specific boost AND MAX_CTR_CAP to click probability
            boost = campaign_click_boost[impression["campaign_id"]]
            # *** MODIFICADO: Aplicar límite MAX_CTR_CAP ***
            actual_click_ratio = min(MAX_CTR_CAP, CLICK_RATIO * boost)

            # Send impression to Kafka
            producer.send(IMPRESSION_TOPIC, key=impression["impression_id"], value=impression)

            # Maybe generate click with adjusted & capped probability
            if random.random() < actual_click_ratio:
                # Add a realistic delay (0.5-10 seconds)
                click_delay = random.randint(500, 10000)  # milliseconds
                click = {
                    "click_id": str(uuid.uuid4()),
                    "impression_id": impression["impression_id"],
                    "user_id": impression["user_id"],
                    "event_timestamp": impression["event_timestamp"] + click_delay
                }
                # Send click to Kafka (SIN el sleep que bloqueaba antes)
                # El productor maneja el envío asíncrono
                producer.send(CLICK_TOPIC, key=click["click_id"], value=click)

            # Control generation rate
            wait_time = 1.0 / EVENT_RATE
            # Ajustar sleep para compensar el tiempo de procesamiento interno mínimo
            processing_time = time.time() - current_time
            sleep_duration = max(0, wait_time - processing_time)
            time.sleep(sleep_duration)

    except KeyboardInterrupt:
        print("Shutting down event generator...")
    finally:
        if 'producer' in locals() and producer:
             print("Flushing producer...")
             producer.flush(timeout=10) # Dar tiempo para enviar mensajes pendientes
             print("Closing producer...")
             producer.close(timeout=10)
             print("Producer closed.")

if __name__ == "__main__":
    main()