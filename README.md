# Employee Attendance App

A Flutter attendance app that marks attendance via on-device face recognition, aiming for a phone-Face-Unlock-like experience: enroll once from a few angles, then just look at the camera to log attendance.

## Status: demo / evaluation build

This build is for internal and client demo/testing purposes — **not for production use with real employee attendance data yet.** See [Licensing](#licensing) below before deploying it for real.

## How recognition works

- **Detection, alignment, embedding extraction, and liveness scoring** all run on-device via [InspireFace](https://github.com/HyperInspire/InspireFace) (Android only for now — see [Platform support](#platform-support)).
- **Live camera preview** (the "face detected" / pose-guidance UI hint while framing a shot) uses Google ML Kit — a separate, lightweight check used only for real-time UX feedback, not for the actual match decision.
- **Enrollment captures 5 poses** (front, left, right, up, down) via `FaceScanScreen`'s `FaceScanMode.enroll` flow, storing one embedding per pose (`Employee.faceEmbeddings`). Left/right prompts rely on a deliberate hold rather than a measured turn angle — ML Kit's yaw angle (`headEulerAngleY`) is only reliable in its slower "accurate" detector mode, and the live preview intentionally runs in "fast" mode for responsiveness. Up/down prompts do use a measured pitch angle (`headEulerAngleX`), which ML Kit's docs don't carry that same caveat for.
- **Login is walk-up 1:N identification** (`FaceRecognitionService.identify`), like phone Face Unlock: no manual ID entry, the scanned face is compared against every enrolled employee's multi-pose profile (best-matching pose per employee), and the top match must both clear `matchThreshold` and beat the runner-up by `matchMargin` to be accepted.
  - **Trade-off to know about:** an earlier version of this app used 1:1 verification (enter Employee ID, then only compare against that one person) specifically because open-set 1:N matching had occasionally matched one employee's face to a different enrolled employee. The margin check plus multi-pose profiles reduce that risk but do not eliminate it the way 1:1 verification did — this needs real benchmark testing (see [Known limitations](#known-limitations--next-steps)) before being trusted in the field.
- **Liveness gating**: every capture (enrollment and login) is checked via InspireFace's RGB liveness score before being accepted; a low/missing score is treated as a spoof attempt and fails closed (rejected), not silently passed.

## Platform support

| Platform | Status |
|---|---|
| Android | Working — verified end-to-end on a physical device (enrollment through all 5 poses, then a walk-up login correctly matching and marking attendance). InspireFace integrated via a Kotlin/JNI bridge (`android/app/.../InspireFaceBridge.kt`) since InspireFace has no Flutter package. |
| iOS | Not yet integrated. InspireFace ships a C API + static library for iOS (`libInspireFace.a` + `inspireface.h`), which would be wired in via Dart FFI rather than a platform channel — that work hasn't been done yet. |

## Licensing

**Read this before showing the app outside internal/client testing.**

- InspireFace's SDK code is open source, but the bundled pretrained models (the actual face recognition accuracy) are licensed for **academic/non-commercial use only**.
- Using this build for internal evaluation, benchmarking, and client demos (with consenting participants) is fine under that license.
- Using it to actually run a company's real attendance/payroll tracking is commercial use and is **not covered** by the current license. That requires contacting InspireFace (`contact@insightface.ai`) for a commercial license before going live.

## Data & consent

Face images are biometric data. Anyone whose face is captured for testing (enrollment or login) should be informed and give consent first — this applies even for internal/demo testing, not just production use.

## Setup

```bash
flutter pub get
flutter run
```

Android requires the JitPack repository (already configured in `android/build.gradle.kts`) to resolve the `com.github.HyperInspire:inspireface-android-sdk` dependency — no manual model download needed, the model pack ships bundled inside that artifact.

Upgrading to this version wipes previously enrolled employees on-device (`DatabaseHelper` bumps the DB schema version because the embedding storage format changed from one embedding per employee to a list of five) — re-enroll after updating.

Local storage now mirrors the backend's schema (`workers`, `worker_tasks`, `departments`, `tasks` tables in `DatabaseHelper`) instead of the old flat `attendance` table — another schema-version bump, so upgrading past this version wipes previously enrolled workers again (re-enroll after updating). Notes for whoever wires up real backend sync:
- `workers.created_by`/`departments.created_by`/`.modified_by` reference an admin-accounts table (`ab_admin` on the backend) that doesn't exist locally — there's no admin/supervisor-accounts table yet, just a single hardcoded credential (`SupervisorAuthRepository`). Local inserts use a placeholder `created_by` (see `DatabaseHelper._placeholderCreatedBy`) until real accounts exist.
- The backend schema's approval workflow (`workers.status`: pending/approved/rejected, `approved_by`, `approved_at`) has no review screen in the app yet, so every local enrollment is written straight to `status = 'approved'`.
- `departments`/`tasks` are populated/created lazily: enrolling a worker looks up (or creates) a `departments` row for whatever free-text department name the supervisor typed, matched case-insensitively. `tasks`/`worker_tasks` exist as schema only — nothing in the app currently assigns tasks to workers.
- SQLite doesn't have MySQL's `ENUM`, so `gender`/`status` etc. are plain `TEXT` columns without a `CHECK` constraint — keep the values in sync with the backend's enum literals by convention, not by DB enforcement.

## Known limitations / next steps

- `matchThreshold` (0.65) and `matchMargin` (0.07) in `lib/face_recognition_service.dart` are starting defaults — validate and tune them against real enrollment photos, particularly across the demographics the app will actually be used with, before trusting them in the field.
- `livenessThreshold` (0.75) is untested against real spoof attempts (printed photo, phone screen replay) — validate before relying on it as a security boundary.
- A device log during testing showed one `InspireFace: Failed to process multiple faces, error code: 1288` during the liveness pipeline step; it didn't block the flow in that run (the match still succeeded), but the cause isn't fully diagnosed — watch for it during further testing.
- iOS integration is outstanding.
- The walk-up 1:N identification trade-off noted above hasn't been stress-tested with multiple similar-looking enrolled employees.
