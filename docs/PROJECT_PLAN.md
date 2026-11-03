# Wi-Fi Fingerprint Indoor Positioning — Living Project Document

> **Status:** Working project plan and integration specification  
> **Repository:** [M-Awad23/wifi_fingerprint](https://github.com/M-Awad23/wifi_fingerprint)  
> **Last documented:** 2026-11-03  
> **Purpose:** Keep the team aligned on what we are building, how the data will be collected and stored, how indoor positioning will work, and how the positioning output will be displayed on the indoor maps produced by the map team.

This document is intentionally a **living document**. Update the status, decisions, milestones, schemas, and open questions whenever implementation or team agreements change. Planned features are labelled as planned; their inclusion here does not mean they are already implemented.

---

## 1. Project vision

Build an indoor positioning system that estimates a phone user's location inside a building and displays that location as a live marker on an indoor floor map.

The system will use multiple sources of information:

1. **Wi-Fi fingerprinting** — identifies locations from nearby access points and their received signal strengths (RSSI).
2. **Pedestrian dead reckoning (PDR)** — estimates movement between reference observations using phone motion sensors.
3. **Magnetic fingerprinting** — uses local magnetic-field patterns to help recognize places and distinguish areas that may look similar to Wi-Fi.
4. **Sensor fusion** — combines the above estimates to produce a more stable position.
5. **Indoor map integration** — transforms the estimated position into the map's coordinate system and renders a moving user marker on the correct floor.

The current application is primarily the **data-collection foundation**. The complete real-time positioning product is a later milestone.

### Intended end-to-end result

A user opens the app, selects a building and floor, and sees their approximate position on the indoor map. As they walk, the marker moves with them. Wi-Fi observations periodically correct accumulated movement error; PDR tracks movement between Wi-Fi observations; magnetic observations can provide additional location cues. The app should also be able to show the estimated floor and a confidence/quality indicator.

---

## 2. Current repository and implementation snapshot

The repository currently contains:

- A Flutter application under `lib/`.
- An Android native implementation at `android/app/src/main/kotlin/com/example/wifi_fingerprint/MainActivity.kt`.
- A Flutter-to-Android method channel named `wifi_fingerprint/scanner`, with a `scanWifi` method.
- A starter ASP.NET Core API project under `backend/WifiFingerprint.Api/`.
- A starter README that is to be replaced with project-specific documentation.

The Flutter screen currently presents session/building/location fields, survey controls, scan status, and a list of Wi-Fi access-point results. The Android implementation uses Android's Wi-Fi APIs and returns fields including SSID, BSSID, RSSI, frequency, and scan timestamp.

**Important current limitations:** the survey controls and scan display are not yet a complete durable collection workflow. The current UI state shown in the app is not, by itself, a reliable saved dataset. The backend project currently contains the default weather-forecast example and is not yet a fingerprint-data API. This document describes the intended architecture, not completed functionality.

### Status summary

| Capability | Status | Notes |
|---|---|---|
| Flutter app scaffold and survey screen | Present | UI exists in `lib/main.dart` |
| Flutter-to-Android Wi-Fi method channel | Present | `wifi_fingerprint/scanner` |
| Native Android Wi-Fi scan results | Present | Android permissions, Location services, and scan throttling affect results |
| Session and reference-location metadata | UI fields present | Must be persisted with each collection session/point |
| Durable local dataset storage | Planned | Must survive app closure and support export/retry |
| Accelerometer and gyroscope collection | Planned | Raw timestamped sensor samples |
| Magnetometer collection | Planned | Raw XYZ values and derived magnitude |
| PDR processing | Planned | Step detection, heading, displacement and drift handling |
| Magnetic fingerprint localization | Planned | Requires labelled calibration data |
| SQL Server persistence/API | Planned | Backend is currently a starter API |
| Wi-Fi KNN/WKNN localization | Planned | Train/evaluate from labelled fingerprints |
| Sensor fusion | Planned | Combine Wi-Fi, PDR and magnetic estimates |
| Indoor map live overlay | Planned | Depends on map-team assets and shared coordinates |

---

## 3. System architecture

The system has two major operating workflows: **survey/collection** and **live positioning**.

### 3.1 Survey and data-collection workflow

```text
Flutter collection app
    |
    +--> Android Wi-Fi scan API
    |       +--> BSSID, SSID, RSSI, frequency, scan timestamp
    |
    +--> Android motion sensor APIs
    |       +--> Accelerometer XYZ
    |       +--> Gyroscope XYZ
    |       +--> Magnetometer XYZ
    |
    +--> Survey metadata
            +--> Session, building, floor, reference point,
                 coordinate, device and collection time
    |
    v
Local durable storage on phone
    |
    +--> Review / validate / export / retry upload
    |
    v
ASP.NET Core API
    |
    v
SQL Server dataset
```

### 3.2 Live positioning workflow

```text
Phone sensors + periodic Wi-Fi scans
             |
             v
       Sensor preprocessing
             |
      +------+------+
      |             |
      v             v
 Wi-Fi matcher    PDR engine
      |             |
      +------+------+
             |
     Magnetic matcher
             |
             v
       Sensor fusion
             |
             v
 Position estimate:
 building, floor, x, y, heading,
 confidence, timestamp
             |
             v
 Flutter indoor map renderer
             |
             v
 Live user marker on the map
```

**Preferred runtime direction:** perform time-sensitive positioning on the phone where practical. The API and SQL Server should manage datasets, map metadata, model/configuration distribution, and optional telemetry. A network round trip should not be required for every sensor sample or every marker update. Offline operation should remain possible after the relevant maps and positioning data are available locally.

---

## 4. Phase plan

The phases are a roadmap, not a claim that all listed work is finished. Some phases can overlap when their interfaces are agreed.

### Phase 1 — Multimodal collection application

**Goal:** collect correctly labelled, timestamped Wi-Fi and motion data using a physical Android phone.

#### 1A. Wi-Fi observations

Capture for each access point returned by Android:

- SSID (may be hidden or empty)
- BSSID (access-point identifier; preserve exact value)
- RSSI in dBm
- Frequency in MHz
- Android scan timestamp where available
- App receipt timestamp (UTC)
- Scan/session identifier

A fingerprint observation consists of the set of access-point measurements observed during one scan at a known reference location. A single scan can include many access points; therefore, model the scan and its AP measurements as separate records.

#### 1B. Motion sensors

Collect raw, timestamped readings from:

- **Accelerometer:** acceleration along X, Y and Z axes. Document whether values include gravity or are gravity-removed.
- **Gyroscope:** angular velocity around X, Y and Z axes.
- **Magnetometer:** magnetic field along X, Y and Z axes (typically reported in microtesla, subject to platform/API details).

Record sensor timestamp, app receipt timestamp if useful, sensor type, sampling interval/rate, and device/session context. Keep raw readings so algorithms can be changed and evaluated later.

Derived values may include:

- Acceleration magnitude.
- Magnetic-field magnitude: `sqrt(mx² + my² + mz²)`.
- Step events and step timestamps.
- Heading estimate and heading quality.
- PDR displacement/trajectory segments.

Do not discard raw sensor data just because derived values are available.

#### 1C. Collection modes

The app should eventually support at least two clearly distinct modes:

**Reference-point survey mode**
- Surveyor chooses building and floor.
- Surveyor chooses or creates a labelled reference point.
- Point has a known map coordinate or a stable survey identifier that can later be mapped to a coordinate.
- Capture repeated Wi-Fi scans and sensor samples at the point.
- Allow notes such as device orientation, approximate location, environment, and issues.

**Walking/trajectory mode**
- Surveyor starts a route from a known start point.
- Record continuous sensor samples and periodic Wi-Fi observations.
- Record route/ground-truth markers when available (turns, checkpoints, endpoints).
- Associate the trajectory with its building and floor.
- Support pause/resume/stop and preserve the session if the app is interrupted.

Reference-point mode builds labelled fingerprints. Walking mode is needed to evaluate PDR and sensor fusion.

#### 1D. Collection quality and reliability

- Use a consistent time base. Prefer UTC wall-clock timestamps for cross-record association and monotonic sensor timestamps for sample ordering/intervals.
- Keep original Android sensor timestamps; do not replace them with only the UI clock.
- Handle missing sensors, permission denial, Wi-Fi disabled, Location services disabled, throttled scans, and empty scan results explicitly.
- Avoid treating an old cached Wi-Fi result as a fresh measurement without marking it.
- Store data locally before upload. Upload should be retryable and should not create duplicate records.
- Include app version and device model/OS information where useful for reproducibility.
- Provide a session review/export path so collected data can be checked before it is used for training.

**Phase 1 completion criteria**
- Real Wi-Fi scans can be captured on supported Android devices.
- Accelerometer, gyroscope and magnetometer samples can be captured with timestamps.
- A scan/session is linked to a building, floor, and reference point or trajectory.
- Data survives application restart and can be exported or uploaded.
- A small pilot dataset can be inspected and validated.

### Phase 2 — Dataset model, backend and preparation

**Goal:** store, validate, query and prepare survey datasets.

Recommended initial logical entities (physical table names can change):

| Entity/table | Purpose |
|---|---|
| `Buildings` | Building identity and metadata |
| `Floors` | Floor identity and map/coordinate metadata |
| `SurveySessions` | One collection visit/run, device and operator metadata |
| `SurveyLocations` | Labelled reference point with floor and known map coordinate |
| `WiFiFingerprintScans` | One Wi-Fi scan event at a time |
| `WiFiAccessPointMeasurements` | One row per AP observed in a scan |
| `SensorReadings` | Timestamped accelerometer, gyroscope and magnetometer samples |
| `TrajectorySegments` | Walking session ranges and start/end references |
| `GroundTruthPoints` | Manually verified checkpoints/coordinates for evaluation |
| `MapAssets` | Map file/version and its coordinate metadata |

#### Suggested relationships

- One building has many floors.
- One floor has many survey locations.
- One survey session belongs to a building and may cover one or more floors.
- One survey location can have many Wi-Fi scans.
- One Wi-Fi scan has many AP measurements.
- One survey session has many sensor readings and trajectory segments.
- Ground-truth points are associated with a session and a floor/location.

#### Example record structure

A Wi-Fi scan should be a parent record with AP measurement children, rather than one repeated row containing a variable number of APs.

Example conceptual JSON:

```json
{
  "sessionId": "session-guid",
  "buildingId": "building-a",
  "floorId": "floor-1",
  "referencePointId": "point-001",
  "capturedAtUtc": "2026-11-03T10:15:30.000Z",
  "device": {
    "model": "Android device model",
    "osVersion": "Android version"
  },
  "accessPoints": [
    {
      "bssid": "AA:BB:CC:DD:EE:FF",
      "ssid": "Example WiFi",
      "rssiDbm": -61,
      "frequencyMhz": 2412
    }
  ]
}
```

This is an illustrative payload, not an existing API contract. Actual API DTOs and schema must be versioned and documented when implemented.

#### SQL Server: what is stored?

The database stores structured records (rows/columns), not a single JSON file per scan. A scan record is stored in a scan table, and each observed access point is stored as a related row in a measurements table. Sensor samples are separate timestamped rows or appropriately batched records. JSON may still be used as an API transfer format or for export, but it is not the only storage model.

Large raw sensor collections can become high-volume. During implementation, measure sample rates and dataset size, then decide whether to store individual rows, upload compressed batches, or use a hybrid. Preserve a lossless export format regardless.

#### How the stored scans are used later

1. Query scans by building, floor and reference point.
2. Convert each scan into a feature representation keyed by BSSID with RSSI values.
3. Align scans that see different access-point sets (missing APs need a consistent policy).
4. Train/calibrate and validate KNN/WKNN or other fingerprint-matching methods.
5. During live operation, compare the phone's current Wi-Fi scan with stored labelled fingerprints.
6. Return an estimated map coordinate and quality/confidence information.
7. Use new verified surveys to improve or recalibrate the fingerprint database.

The original measurements remain the source dataset. Training features and model artefacts should be reproducible from them.

### Phase 3 — Wi-Fi fingerprint localization

**Goal:** estimate a user's position from a live Wi-Fi scan by comparing it with labelled survey fingerprints.

Initial algorithm candidates:
- **K-Nearest Neighbors (KNN):** find the K most similar stored fingerprints and use their labels/coordinates.
- **Weighted KNN (WKNN):** give closer matches greater influence when calculating the estimated coordinate.

Implementation considerations:
- Choose and document a distance metric.
- Handle access points absent from either scan.
- Normalize or calibrate RSSI carefully; avoid inventing signal values without recording the missing-data policy.
- Test sensitivity to phone model, phone orientation, time of day, people, doors and environmental changes.
- Use a validation set or held-out collection sessions. Do not evaluate only on the same scans used to build the reference database.
- Report positioning error in metres, not only classification accuracy.

### Phase 4 — PDR and magnetic positioning

**PDR** estimates the path travelled from a known starting state:
- Detect steps from acceleration patterns.
- Estimate step length (initially a calibrated or simple model, later a user/device-adaptive model if justified).
- Estimate heading using orientation/motion information, with careful handling of sensor coordinate frames and device orientation.
- Update position from step length and heading.
- Track uncertainty because step-length and heading errors accumulate over time.

**Magnetic fingerprinting**:
- Collect magnetic XYZ readings and magnitude at labelled positions and along trajectories.
- Build spatial magnetic signatures from repeated observations.
- Match live magnetic measurements/patterns to the surveyed magnetic dataset.
- Treat magnetic readings as environment-dependent; moving metal objects, devices, doors and building changes can affect the field.

PDR and magnetic localization are not the same technique: PDR estimates movement from a starting point, while magnetic fingerprinting compares sensed field patterns with previously collected location data.

### Phase 5 — Sensor fusion

**Goal:** combine Wi-Fi, PDR and magnetic evidence into one position estimate.

Conceptual roles:
- Wi-Fi provides absolute-ish location corrections when a useful scan is available.
- PDR provides continuous relative movement between Wi-Fi observations but drifts over time.
- Magnetic fingerprints may provide additional place recognition/correction where they are distinctive and stable.

Possible approaches include complementary filtering, probabilistic filtering (e.g. Kalman-family methods where assumptions are appropriate), particle filtering, or confidence-weighted correction. Select an approach only after examining the collected data and measured error.

The fusion engine should track uncertainty. Do not treat a confidence value as a calibrated probability unless it has been calibrated and evaluated.

### Phase 6 — Indoor map integration and real-time position layer

**Goal:** display the estimated position on the floor maps produced by the map-design team.

This is the key integration point between the positioning work and the mapping work.

#### Map-team deliverables

For each building/floor, the map team should provide:

1. A map asset (preferably a structured vector format such as SVG/GeoJSON where practical; a raster PNG can also work).
2. Stable building and floor identifiers.
3. Map width/height and units.
4. A defined coordinate system: origin, X direction, Y direction, axis orientation, and unit (preferably metres for the positioning interface).
5. A known transformation between map coordinates and displayed pixels/vector coordinates.
6. Walkable areas/obstacles if routing or map-constrained positioning is required.
7. Optional navigation graph: nodes and walkable edges for pathfinding.
8. A version identifier so survey data can be tied to the correct map revision.

The positioning team must know how every surveyed reference point maps to this coordinate system. A label such as “Room 101” is not enough by itself; the reference point needs an explicit coordinate or a repeatable mapping process.

#### Coordinate alignment contract

Both teams must agree on one canonical coordinate convention before large-scale collection.

Recommended convention:
- Positioning coordinates are in **metres**.
- Origin `(0, 0)` is a clearly marked point on each floor.
- `+X` and `+Y` directions are defined in the floor metadata.
- Floor is represented by a stable `floorId`, not inferred from Y/Z.
- Heading convention is documented (e.g. degrees clockwise from map +Y/north); do not assume compass heading and map heading are identical.
- Pixel conversion, if needed, is performed by the map renderer using the agreed transform.

For a simple raster map, a coordinate-to-pixel transform may be expressed as:

```text
pixelX = originPixelX + (xMetres * pixelsPerMetreX)
pixelY = originPixelY - (yMetres * pixelsPerMetreY)
```

The sign on Y depends on the image coordinate convention (image Y often increases downward). The actual transform must be derived from map metadata/control points, not guessed. For rotated, skewed or georeferenced maps, use an affine or appropriate vector transform instead of a simple scale.

#### Shared live-position message

The positioning engine should expose a stable, renderer-independent position object. Initial proposed JSON contract:

```json
{
  "buildingId": "building-a",
  "floorId": "floor-1",
  "x": 12.4,
  "y": 8.7,
  "headingDegrees": 95.0,
  "confidence": 0.92,
  "horizontalAccuracyMeters": 1.8,
  "timestampUtc": "2026-11-03T10:15:30.000Z",
  "source": "wifi+pdr+magnetic"
}
```

This is a proposed interface. Confirm heading convention, confidence semantics, accuracy calculation, units, and nullable fields before implementation. The interface must make it possible to distinguish a stale or low-quality fix from a fresh reliable one.

#### Runtime integration sequence

1. User selects a building and floor.
2. App loads the matching map asset and map metadata.
3. App obtains sensor samples and periodic Wi-Fi scans.
4. Positioning engine calculates an estimate in the floor's canonical coordinate system.
5. Engine publishes a position update through an in-process stream/callback (or another agreed interface).
6. Flutter map renderer transforms `(x, y)` into map coordinates and draws the user marker.
7. Marker orientation follows heading; visual treatment can reflect uncertainty/quality.
8. If floor estimate changes, app switches to the corresponding floor map only after applying an agreed floor-transition policy.

**Recommended first integration:** keep the positioning engine and map renderer in the same Flutter app and communicate through an in-process position stream. Add API/WebSocket transport only if another client or remote consumer actually needs live positions. Avoid sending every raw sensor sample to the map team or map renderer; the renderer needs position updates, not raw accelerometer events.

#### Team responsibilities

| Mapping team | Positioning/collection team |
|---|---|
| Produce floor map assets | Collect labelled Wi-Fi and sensor data |
| Define building/floor IDs | Maintain matching building/floor IDs |
| Define map coordinate origin, units and axes | Survey reference points in the same coordinate system |
| Supply map dimensions and transforms | Output position in canonical map coordinates |
| Provide walkable areas and optional routing graph | Provide position estimates, heading, time and quality |
| Version map assets and metadata | Version datasets against map revisions |

Both teams must jointly test at surveyed control points. A marker that appears in the wrong room usually indicates a coordinate transform, origin, floor mapping, or stale-map mismatch—not necessarily a Wi-Fi algorithm problem.

### Phase 7 — Testing and evaluation

Evaluate each component independently and then the complete fused system.

Recommended measures:
- Mean positioning error (metres).
- Median error and 90th-percentile error.
- Percentage of estimates within agreed thresholds (e.g. 1 m, 2 m, 5 m).
- Update frequency and end-to-end latency.
- Time to first fix.
- Floor detection accuracy.
- PDR drift over route length/time.
- Wi-Fi-only vs PDR-only vs magnetic-only vs fused performance.
- Robustness across devices, orientations, occupancy levels and collection days.
- Battery and thermal impact.

Testing should include stationary points, straight corridors, turns, rooms, corridor intersections, vertical transitions, and difficult areas with weak or similar Wi-Fi fingerprints.

---

## 5. Proposed data and time conventions

### Identifiers

Use stable IDs for buildings, floors, survey sessions, reference points, scans, and map versions. Prefer GUID/UUID identifiers for generated records. Human-readable labels are useful metadata but should not be primary keys.

### Timestamps

Store:
- UTC wall-clock timestamp for cross-system association.
- Original monotonic sensor timestamp (or platform timestamp) for sample timing and integration.
- Explicit units for timestamp fields.

Never assume timestamps from different clocks can be subtracted safely without understanding their clock basis. Retain enough information to align sensor samples with Wi-Fi scans.

### Coordinate values

- Use floating-point metres for canonical indoor X/Y coordinates.
- Keep the floor as a separate identifier.
- Store the coordinate-system/map-version identifier with surveyed coordinates.
- Do not silently move survey points when a map is revised; preserve the map version and define a migration/re-survey process.

### Wi-Fi identity and privacy

BSSID is used as an access-point identifier for fingerprint matching. Keep it in the dataset where required by the project. Avoid collecting unrelated personal data. Restrict access to raw survey data and define retention/sharing rules with the project supervisor/team.

---

## 6. Proposed software stack

| Layer | Intended technology | Responsibility |
|---|---|---|
| Collection and map UI | Flutter / Dart | Survey flows, data review, indoor map and live marker |
| Android device integration | Kotlin, Android Wi-Fi APIs, Android sensor APIs | Wi-Fi scans and sensor events |
| Local persistence | SQLite or another appropriate local database | Durable offline collection and upload queue |
| Backend API | ASP.NET Core | Upload, validation, queries, metadata and dataset management |
| Central database | Microsoft SQL Server | Structured survey and map metadata |
| Processing/experimentation | Python | Dataset analysis, baseline algorithms, plots and evaluation |
| Runtime positioning | Start with a testable implementation; integrate into Flutter/native Android as appropriate | On-device estimates and sensor fusion |
| Map assets | Agreed vector/raster format | Floor rendering and coordinate transform |

Technology choices can change. Keep API schemas and data formats independent enough that experimentation in Python does not lock the mobile app to one implementation.

---

## 7. Immediate priorities

The most useful next work, in order:

1. **Finish and verify real Android Wi-Fi capture** on the target physical phone, including permission and scan-throttling behavior.
2. **Agree on a timestamp and collection metadata model** before adding more sensors.
3. **Add accelerometer, gyroscope and magnetometer collection** with original sensor timestamps.
4. **Implement local durable storage** for sessions, locations, scans, AP measurements and sensor samples.
5. **Add survey and walking modes**, including labelled reference points and route checkpoints.
6. **Define the map/positioning coordinate contract with the map team now**, before collecting a large dataset.
7. **Replace the starter backend endpoint** with versioned collection/upload APIs and SQL Server persistence.
8. **Create and validate a small pilot dataset** before scaling collection.
9. Implement Wi-Fi baseline localization, then PDR/magnetic methods, then fusion.
10. Integrate the position stream with the floor-map renderer and evaluate the full system.

---

## 8. Decisions and open questions

Keep this section current. Mark a question resolved only after the team agrees and documents the chosen value.

| Topic | Current proposal / question | Status |
|---|---|---|
| Target platform | Android phone first; Flutter UI with native Android sensor/Wi-Fi access | Proposed |
| Wi-Fi fingerprint key | BSSID plus RSSI and frequency per scan | Proposed |
| Sensor sampling rates | Determine supported rates and battery/data trade-offs on target devices | Open |
| Timestamp strategy | UTC capture time plus original monotonic sensor timestamps | Proposed |
| Local storage | SQLite or equivalent offline-first storage | Open |
| Central database | SQL Server | Planned |
| API | ASP.NET Core | Starter project exists; data API not implemented |
| Map format | SVG/GeoJSON preferred where useful; PNG also supported | Joint decision needed |
| Coordinate unit | Metres | Proposed |
| Coordinate origin/axes | One defined origin and axis orientation per floor | Map-team decision needed |
| Heading convention | Document degrees reference and rotation direction | Open |
| Floor identifiers | Stable building/floor IDs shared by both teams | Joint decision needed |
| Position update transport | In-process stream inside app initially | Proposed |
| Fusion algorithm | Select after data collection and baseline evaluation | Open |
| Ground truth | Survey points and/or independently verified trajectories | Open |
| Evaluation thresholds | Agree acceptable error and update latency with project stakeholders | Open |

---

## 9. Documentation and change-control rules

To keep this document useful:

- Update the **current implementation snapshot** whenever a feature is completed, changed, or removed.
- Change a roadmap item from Planned to In progress or Implemented only when the code and tests support that status.
- Record important architecture decisions in the Decisions section, including the date and reason.
- When an API payload or database schema is implemented, link to its source file/migration and update the examples here.
- When the map team provides an asset or coordinate specification, record its version and link it here.
- Keep sample payloads clearly labelled as illustrative until they match the implemented DTO/schema.
- Do not delete historical decisions without recording why they changed.

### Change log

| Date | Update |
|---|---|
| 2026-11-03 | Initial living plan covering Wi-Fi, PDR, magnetic sensing, sensor fusion, dataset storage, and indoor-map live positioning integration. Repository inspected; existing code and planned capabilities distinguished. |

---

## 10. Definition of the finished system

The project is considered integrated when:

- A surveyor can collect repeatable, labelled Wi-Fi and multimodal sensor datasets.
- Data is saved locally and centrally without loss or accidental duplication.
- The system can estimate a live position and floor from Wi-Fi/PDR/magnetic inputs, with quality information.
- Position estimates use the same coordinate system as the indoor maps.
- The Flutter application renders a stable, correctly aligned live marker on the correct floor.
- The system has been tested against independent ground truth and its error/latency limitations are documented.

The final deliverable is therefore **not just a database of scans or a static map**. It is an indoor positioning pipeline connected to a map interface, supported by a repeatable data-collection and evaluation process.
