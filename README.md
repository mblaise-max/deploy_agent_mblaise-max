# Deploy Agent

A gentle, single-file bootstrapper for the Student Attendance Tracker. One script (`deploy_agent.sh`) deploys the project, runs it, and archives its logs, and it cleans up after itself if you interrupt it.

## Layout
```
deploy_agent.sh
templates/            <- the three UNMODIFIED source files
  attendance_checker.py
  assets.csv
  config.json
```

## Running it
```bash
chmod +x deploy_agent.sh
./deploy_agent.sh                    # friendly numbered menu (1 deploy, 2 run, 3 archive, 4 leave)
./deploy_agent.sh deploy [name]      # Feature 1
./deploy_agent.sh run [name]         # Feature 2
./deploy_agent.sh archive [name]     # Feature 3
./deploy_agent.sh help
```
Both menu and flags are supported. `name` is optional: with run/archive the script finds existing `attendance_tracker_*` folders and lets you pick if there are several.

## Feature 1 - Deploy
1. **Pre-flight:** checks `python3` (prints `python3 --version`), `zip`, and that `templates/` is complete. It stops before creating anything if something is missing.
2. **Name:** only letters, numbers, `-` and `_` are accepted, so there are no surprise paths. If `attendance_tracker_<name>/` exists you are asked whether to replace it; "no" leaves it untouched.
3. **Structure:** `attendance_tracker_<name>/{attendance_checker.py, Helpers/{assets.csv,config.json}, reports/}`.
4. **Roster:**
   - **A** copies N rows (plus header) from `templates/assets.csv` (N is validated against the template size).
   - **B** generates N rows from name arrays in the script, counts at `0,0`.
5. **total_sessions stays consistent:** Option A rows carry 4 prior sessions, so `total_sessions = 5`. A fresh Option B roster has none, so `total_sessions = 1`. The script sets this with `sed`; nothing else in `config.json` changes.
6. **Permissions:** `chmod +x` on the app, `chmod 600` on `Helpers/config.json`; the resulting modes are printed.
7. **Thresholds (optional):** answer `y`, then enter warning (default 75) and failure (default 50). Input must be digits only, at most 100, and failure must be lower than warning, otherwise you are asked again. The values are written with `sed` against the `"warning": N` and `"failure": N` lines only, so formatting and order are preserved.
8. **Verify:** the deploy ends by launching the app (Feature 2). A clean start proves structure, roster and config fit together.

## Feature 2 - Run
`cd attendance_tracker_<name> && python3 attendance_checker.py`, in a subshell so your own working directory is not changed.

## Feature 3 - Archive
Checks `reports/attendance.log` and `reports/absent.log`. Each existing log is **copied** to its own folder with one shared timestamp:
```
attendance_tracker_<name>/archives/attendance/attendance_YYYYMMDD_HHMMSS.log
attendance_tracker_<name>/archives/absent/absent_YYYYMMDD_HHMMSS.log
```
A missing log (e.g. nobody was absent) is reported kindly and skipped; the script never crashes. Originals stay in `reports/`.

## Ctrl+C / Ctrl+Z during deploy
`SIGINT` and `SIGTSTP` are trapped from the moment the project folder is about to be created until setup finishes. The trap is released before the app launches, so it never interferes with a marking session. On interrupt the script:
1. explains what happened,
2. zips whatever exists into `attendance_tracker_<name>_archive.zip` (using `zip -r`),
3. deletes the half-built folder,
4. exits cleanly (status 130).

**To test:** start `./deploy_agent.sh deploy test1`, answer the name prompt, then press Ctrl+C (or Ctrl+Z) at the roster question. Inspect the zip with `unzip -l attendance_tracker_test1_archive.zip`. It contains the partial project (folders, the copied app and config at that moment). If a step fails for another reason (e.g. permission denied), the partial project is removed and the reason is shown.

## How I tested the deployed structure
- Deployed with Option A and Option B, confirmed with `find attendance_tracker_<name> -type f` that the layout matches the spec.
- Checked `ls -l` modes (`-rwxr-xr-x` app, `-rw-------` config) and diffed `templates/` to confirm it was untouched.
- Confirmed `total_sessions` is 5 (A) / 1 (B) and thresholds changed in place via `cat Helpers/config.json`.
- Entered bad input (letters, empty, 0 students, failure >= warning) and existing-folder "no"/"yes" paths.
- Ran the app, archived with and without `absent.log`, and sent SIGINT and SIGTSTP mid-deploy.
