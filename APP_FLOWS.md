# App Flows (current, local)

What actually happens when a supervisor uses the app today, based on the code
as it stands. This only describes flows a screen can actually reach right
now — a section at the bottom lists code that exists but has no button
pointing to it.

## 1. Login

`login_screen.dart` → `SupervisorLoginViewModel.login()` →
`SupervisorAuthRepository.authenticate()` → `POST /auth/verifyUser`.

- Real backend call, not a hardcoded credential.
- On success: the bearer token is stored (`ApiTokenRepository`, used by every
  later request via `AuthInterceptor`), the full login response is saved to
  `SharedPreferences` (`SupervisorSessionRepository`), and the supervisor's
  timezone from that response is applied (`AppTime.setTimeZone`).
- Lands on the Dashboard, nav stack cleared.

## 2. Enroll a worker

From the Worker List screen's "Enroll Worker" FAB:

```
EnrollmentFormScreen → FaceCaptureScreen → EnrollmentCompleteScreen
```

- `EnrollmentFormScreen`: name, DOB, department, pay type, National ID +
  photo. Validates the National ID isn't already enrolled.
- `FaceCaptureScreen`: captures face embeddings for the worker.
- On success, the worker is inserted into the local `workers` table with
  `is_synced = 0` and `status = 'pending'` — every new worker starts
  unsynced until pushed to the backend (see §3).
- `EnrollmentCompleteScreen` offers "Back to Worker List" or "Enroll Another
  Worker".

## 3. Sync a worker to the backend

On the Worker List screen, each worker card has a **Sync** / **Not synced**
button (in the sync row under the work-status/verification line):

```
Worker card "Sync" → WorkerSyncRepository.syncWorker() → POST /attendance/sync-worker
```

Tappable again even after syncing, to push again. This is what the Worker
List's "SYNCED" / "NOT SYNCED" summary counts at the top of the screen are
counting.

## 4. Fetch the full roster from the server

Worker List header's cloud-download icon:

```
WorkerImportRepository.importFromRemote() → POST /attendance/list
```

Upserts every worker from the backend into the local DB, matched by
National ID. If a worker's response row includes `task_ids`, those are
also auto-assigned locally (matched against the local `tasks` cache) —
so a worker can arrive with tasks already on their checklist without
anyone touching the Assign Task screen.

## 5. View / assign tasks ("Day Details")

Worker List card's **View tasks** button opens `AssignTaskScreen` for that
worker — always, even if nothing's assigned yet. It has two independent
parts:

- **Assigned Tasks checklist** (top): shows today's assigned tasks, each
  with an "Is Completed" Yes/No toggle and (UI-only, not persisted) a
  "Verify" Yes/No toggle. Toggling doesn't write anything by itself — the
  **Save** button under the checklist writes the current toggle states
  to the local `worker_task_completion` table and confirms with a snackbar.
- **Assign a new task** (below): pick a department, then a task from that
  department's list; picked tasks show up immediately in the checklist
  above as "Pending". The **Assign Task** button at the very bottom
  commits the current department + task selection to the local
  `worker_tasks` table (adds/removes as needed).

Note: the Attendance/check-in details section that used to sit above the
checklist on this screen is currently commented out in the code, so this
screen no longer shows check-in/check-out times or an attendance sync
retry — see the "Not currently reachable" section below.

## 6. Mark attendance (face scan check-in / check-out)

Reachable two ways: the splash screen's "Mark Attendance" (worker types
their own ID), or a worker card's **Check in** / **Check out** button
(pre-fills that worker's ID and starts the scan automatically).

```
MarkAttendanceScreen → FaceScanScreen (face match) → DatabaseHelper.recordWorkerScan()
```

- First scan of the day → checked in.
- Second scan → checked out, and if a supervisor initiated it (from the
  worker card), it also opens `TaskStatusScreen` with editable Yes/No
  toggles per assigned task (the worker's own self-service kiosk checkout
  opens the same screen read-only instead).
- Third+ scan same day → no-op.

## 7. Worker Report

Worker List card's **Worker report** button opens `WorkerReportScreen` for
that worker: a date-range picker, a period summary (days present / tasks
completed / days synced over the range), and a day-by-day "Daily Activity"
list. Each day has a **View day details** link that opens a read-only
breakdown of that single day's check-in/out and task checklist.

## 8. Bottom navigation

Four tabs, each resetting the nav stack when tapped: **Dashboard**,
**Employees** (Worker List), **Reports** (all-workers `WorkerHistoryScreen`
— different from the per-worker Worker Report in §7), **Settings**
(currently just a Logout tile).

---

## Not currently reachable (code exists, no button leads to it)

Worth knowing about before assuming a "Sync X" action is happening
somewhere it isn't:

- **Pushing task assignments to the backend** (`POST /attendance/assigntask`,
  `TaskSyncRepository.syncWorkerTasks`) — no screen calls this anymore.
  Tasks assigned via §5 stay local-only.
- **Pushing today's attendance record to the backend**
  (`POST /attendance/check-in`, `WorkerAttendanceRepository.syncToday`) —
  its only UI hook was the Attendance section's Retry button on the Day
  Details screen, which is commented out (see §5's note). Check-ins/outs
  from §6 stay local-only.

  Confirmed request body (`worker_attendance_sync_api.dart`):
  ```json
  {
    "worker_id": 47,
    "attendance_date": "2026-09-29",
    "check_in_time": "2026-09-29T02:32:00.000Z",
    "check_out_time": "2026-09-29T10:08:00.000Z",
    "check_in_face_verified": 1,
    "check_out_face_verified": 1
  }
  ```
  Confirmed success response:
  ```json
  {
    "message": "Attendance recorded",
    "attendance_id": 512,
    "status": true
  }
  ```
  (`check_out_time`/`check_out_face_verified` would be `null`/`0` if only
  checked in so far — the endpoint is called again at checkout to fill
  those in.)

- **Pushing task completions to the backend**
  (`POST /attendance/worker-task-completion`,
  `TaskCompletionSyncRepository.syncWorkerTaskCompletions`) — the "Save"
  button in §5 only writes locally; nothing currently pushes that data to
  the server.

  Confirmed request body (`task_completion_sync_api.dart`), one call per
  task:
  ```json
  {
    "worker_task_id": 231,
    "attendance_id": 512,
    "completed_date": "2026-09-29T10:05:00.000Z",
    "supervisor_id": 1,
    "worker_id": 47,
    "status": "yes"
  }
  ```
  Confirmed success response:
  ```json
  {
    "message": "Task completion recorded",
    "completion_id": 908,
    "status": true
  }
  ```
  `status` here is `"yes"` or `"no"` (not a boolean) — it mirrors the
  worker's Is Completed toggle. All the `*_id` fields must be the
  backend's real ids, not local ones, which is why this sync can't run
  until the worker, the attendance day, and the task assignment have each
  been synced first (see `TaskCompletionSyncRepository`'s own skip logic).
- A hardcoded-PIN screen (`AppRoutes.pin`) and an older enrollment screen
  (`AppRoutes.createAttendance` / `CreateAttendanceScreen`) are registered
  routes with no navigation call anywhere.
- `EnrollmentFormScreen`'s edit-worker mode (`editingWorker`) is never
  populated by any call site — there's currently no "edit worker" entry
  point in the UI.

In short: **worker records** and **the full-roster fetch** are the only
two things that currently sync to the backend. Task assignments, task
completions, and attendance check-ins are recorded locally but stay on
the device until something is wired up to push them.
