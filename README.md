# Wi-Fi Fingerprint Indoor Positioning

A multimodal indoor positioning project built around Wi-Fi fingerprinting, pedestrian dead reckoning (PDR), magnetic sensing, and an indoor-map positioning overlay.

## Project goal

Collect labelled Wi-Fi and phone-sensor observations, use them to develop and evaluate indoor localization methods, and ultimately display a user's estimated real-time position on the correct indoor floor map.

The project roadmap includes:
- Wi-Fi fingerprint collection and KNN/WKNN localization.
- Accelerometer and gyroscope collection for PDR.
- Magnetometer collection and magnetic fingerprinting.
- Sensor fusion to reduce drift and improve location estimates.
- ASP.NET Core APIs and SQL Server for central dataset management.
- Flutter indoor-map rendering with a live position marker.

## Current implementation

The repository currently contains a Flutter survey UI, an Android native Wi-Fi scanning method channel, and a starter ASP.NET Core API project. The backend is not yet the fingerprint-data API, and durable multimodal storage, localization algorithms, sensor fusion, and the live map layer remain planned work.

## Documentation

The main source of truth for the system design and roadmap is:

- **[Living Project Plan](docs/PROJECT_PLAN.md)** — architecture, phase-by-phase implementation plan, sensor/data requirements, proposed database model, map-team integration contract, coordinate conventions, evaluation strategy, open decisions, and change log.

## Current priority

Complete and verify reliable Wi-Fi capture on a physical Android phone, then add timestamped accelerometer, gyroscope, and magnetometer collection with durable local storage. Coordinate conventions should be agreed with the map-design team before large-scale fingerprint surveying begins.

