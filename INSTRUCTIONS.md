# Ad Click Analytics: Flink Take-Home Test

## Overview
In this take-home test, you will implement a real-time analytics pipeline using Apache Flink. The pipeline will process ad impression and click events to calculate various metrics that are commonly used in ad-tech platforms.

Your task is to develop Flink jobs that read from Kafka topics, process the data, and produce results that can be visualized or queried.

## Scenario
You're working for an ad-tech company that needs to process two types of events:
1. **Ad Impressions** - When an ad is shown to a user
2. **Ad Clicks** - When a user clicks on an ad

You need to build a real-time pipeline that computes:
1. Click-through rate (CTR) by ad campaign in 1-minute windows
2. User engagement metrics by device type

## Requirements

### Environment
- All components should run in Docker containers
- Use Docker Compose to define the entire environment
- Include Kafka, Flink, and any other necessary components

### Data Processing
- Create Flink tables that source from Kafka topics
- Implement time-based windows for aggregation
- Join impression and click events
- Calculate required metrics
- Output results to a Kafka topic

## Test Data
The system produces events with the following structure:

**Ad Impression Event:**
```json
{
  "impression_id": "imp-123456789",
  "user_id": "user-123",
  "campaign_id": "camp-456",
  "ad_id": "ad-789",
  "device_type": "mobile",
  "browser": "chrome",
  "event_timestamp": 1647890123456,
  "cost": 0.01
}
```

**Ad Click Event:**
```json
{
  "click_id": "click-987654321",
  "impression_id": "imp-123456789",
  "user_id": "user-123",
  "event_timestamp": 1647890128456
}
```

## Deliverables
1. A GitHub repository with all code and documentation
2. Docker Compose configuration for running the entire test
3. Flink jobs that implement the required processing (In Flink SQL, or using Pyflink)
4. A simple way to visualize or query the results

### Repository Structure
Your repository should include:
- An updated `docker-compose.yml` file
- A directory with Flink jobs
- The data generator that produces test events
- A README.md with instructions for running your solution
- Any additional scripts needed for setup

## Evaluation Criteria
You will be evaluated on:
1. Correct implementation of Flink jobs
2. Proper use of Flink concepts (tables, time handling, windows)
3. Code organization and documentation
4. Ability to handle different types of joins and aggregations
5. Overall system architecture and containerization

## Bonus Points (Optional)
- Add anomaly detection
- Add unit tests for your Flink jobs
- Implement a simple dashboard to visualize the metrics

## Time Expectation
This test is designed to be completed in about 3-4 hours. Focus on getting the core requirements working rather than implementing every possible feature.