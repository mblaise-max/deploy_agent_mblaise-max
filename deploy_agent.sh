#!/usr/bin/env bash
# =============================================================================
# deploy_agent.sh - a gentle project bootstrapper for the Attendance Tracker
#
#   ./deploy_agent.sh              open the friendly menu
#   ./deploy_agent.sh deploy [name]   Feature 1: set up a new project
#   ./deploy_agent.sh run [name]      Feature 2: run the tracker
#   ./deploy_agent.sh archive [name]  Feature 3: archive the session logs
#   ./deploy_agent.sh help            show this guide
#
# Projects live next to this script; templates come from ./templates/.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES="$SCRIPT_DIR/templates"
cd "$SCRIPT_DIR" || { echo "Cannot enter $SCRIPT_DIR"; exit 1; }

# ---------- a little warmth: colours only when talking to a real terminal ----
if [[ -t 1 ]]; then
  C_OK=$'\e[32m'; C_WARN=$'\e[33m'; C_ERR=$'\e[31m'; C_DIM=$'\e[2m'; C_B=$'\e[1m'; C_OFF=$'\e[0m'
else
  C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""; C_B=""; C_OFF=""
fi
say()  { printf '%s\n' "$*"; }
ok()   { printf '%s  ✓ %s%s\n' "$C_OK" "$*" "$C_OFF"; }
note() { printf '%s  · %s%s\n' "$C_DIM" "$*" "$C_OFF"; }
warn() { printf '%s  ! %s%s\n' "$C_WARN" "$*" "$C_OFF"; }
oops() { printf '%s  ✗ %s%s\n' "$C_ERR" "$*" "$C_OFF" >&2; }
head1() { printf '\n%s%s%s\n' "$C_B" "$*" "$C_OFF"; }

# ---------- input helpers ----------------------------------------------------
# ask "prompt" VAR [default]  - exits kindly if input ends (Ctrl+D / closed pipe)
ask() {
  local prompt="$1" __var="$2" def="${3-}" reply
  if [[ -n "$def" ]]; then prompt="$prompt [$def]"; fi
  if ! read -r -p "$prompt: " reply; then
    echo; say "No more input - stopping here. Nothing has been harmed."; exit 0
  fi
  printf -v "$__var" '%s' "${reply:-$def}"
}
yes_no() {   # yes_no "question" [default y|n]  -> returns 0 for yes
  local q="$1" def="${2:-n}" a
  while true; do
    ask "$q (y/n)" a "$def"
    case "${a,,}" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *) warn "A simple y or n will do." ;;
    esac
  done
}
is_int() { [[ "$1" =~ ^[0-9]+$ ]]; }

# ---------- project naming ---------------------------------------------------
PROJECT_NAME=""; PROJECT_DIR=""
pick_name() {   # for deploy: ask for a safe name
  local given="${1-}" raw
  while true; do
    if [[ -n "$given" ]]; then raw="$given"; given=""; else ask "What would you like to call this project (e.g. cohort7)" raw; fi
    if [[ "$raw" =~ ^[A-Za-z0-9_-]+$ ]]; then
      PROJECT_NAME="$raw"; PROJECT_DIR="attendance_tracker_$raw"; return
    fi
    warn "Please use only letters, numbers, dashes or underscores (no spaces or slashes)."
  done
}
find_existing() {  # for run/archive: reuse an existing project
  local given="${1-}" found=() d choice
  if [[ -n "$given" && -d "attendance_tracker_$given" ]]; then
    PROJECT_NAME="$given"; PROJECT_DIR="attendance_tracker_$given"; return 0
  fi
  for d in attendance_tracker_*/; do [[ -d "$d" ]] && found+=("${d%/}"); done
  if (( ${#found[@]} == 0 )); then
    oops "I couldn't find any deployed project yet."
    note "Run './deploy_agent.sh deploy' first - it only takes a minute."
    return 1
  fi
  if (( ${#found[@]} == 1 )); then
    PROJECT_DIR="${found[0]}"
  else
    say "Which project do you mean?"
    local i=1; for d in "${found[@]}"; do say "   $i) $d"; ((i++)); done
    while true; do
      ask "Pick a number" choice
      if is_int "$choice" && (( choice>=1 && choice<=${#found[@]} )); then PROJECT_DIR="${found[choice-1]}"; break; fi
      warn "That number isn't on the list."
    done
  fi
  PROJECT_NAME="${PROJECT_DIR#attendance_tracker_}"
  note "Using $PROJECT_DIR"
}

# =============================================================================
# FEATURE 1 - DEPLOY
# =============================================================================
DEPLOYING=0          # 1 only while the setup steps run (that is when we guard)
CREATED_BY_US=0

preflight() {
  head1 "Step 1 · Checking your toolbox"
  local missing=0
  if command -v python3 >/dev/null 2>&1; then ok "python3 found: $(python3 --version 2>&1)"
  else oops "python3 is missing. Install it (e.g. 'sudo apt install python3') and try again."; missing=1; fi
  if command -v zip >/dev/null 2>&1; then ok "zip found"
  else oops "zip is missing. Install it (e.g. 'sudo apt install zip') and try again."; missing=1; fi
  local f
  for f in attendance_checker.py assets.csv config.json; do
    if [[ -f "$TEMPLATES/$f" ]]; then :; else oops "templates/$f is missing - it should sit beside this script."; missing=1; fi
  done
  (( missing )) && { say; say "Nothing was created. Fix the above and I'll be ready when you are."; exit 1; }
}

# Called when Ctrl+C / Ctrl+Z arrives mid-deploy
on_interrupt() {
  trap '' INT TSTP        # don't let a second keypress interrupt the cleanup
  echo; echo
  warn "Deployment interrupted ($1). No worries - let's tidy up gently."
  if [[ -n "$PROJECT_DIR" && -d "$PROJECT_DIR" ]]; then
    local zipname="${PROJECT_DIR}_archive.zip"
    rm -f "$zipname"
    if zip -r -q "$zipname" "$PROJECT_DIR"; then
      ok "Saved what existed so far to $zipname"
      note "Contents: $(zip -sf "$zipname" | tail -n 1 | sed 's/^ *//')"
      if rm -rf "$PROJECT_DIR"; then ok "Removed the half-built $PROJECT_DIR so your workspace stays clean"
      else warn "Couldn't remove $PROJECT_DIR - you may want to delete it by hand."; fi
    else
      oops "Couldn't create the zip, so I've left $PROJECT_DIR untouched for you to inspect."
    fi
  else
    note "Nothing had been created yet, so there is nothing to archive."
  fi
  say; say "Session closed cleanly. Run the deploy again whenever you're ready."
  exit 130
}

# Called when a step fails (e.g. permission denied) - clean up what we made
fail_deploy() {
  oops "$1"
  note "${2:-Check that you have write permission in this folder.}"
  if (( CREATED_BY_US )) && [[ -d "$PROJECT_DIR" ]]; then
    rm -rf "$PROJECT_DIR" && note "I removed the partly built $PROJECT_DIR so nothing is left behind."
  fi
  trap - INT TSTP
  exit 1
}

build_roster_template() {   # Option A
  local file="$1" total n
  total=$(tail -n +2 "$TEMPLATES/assets.csv" | grep -c .)
  while true; do
    ask "How many students to copy (1-$total)" n
    if is_int "$n" && (( n>=1 && n<=total )); then break; fi
    warn "Please enter a whole number between 1 and $total."
  done
  head -n $((n+1)) "$TEMPLATES/assets.csv" > "$file" || fail_deploy "Couldn't write the roster."
  SESSIONS=5
  ok "Copied $n student(s) from the template (each already has 4 past sessions)"
}

build_roster_fresh() {      # Option B
  local file="$1" n i first last email
  local FIRST=(Amara Brian Chloe David Esther Felix Grace Hassan Imani Jonah Kemi Liam)
  local LAST=(Mugisha Okafor Nkurunziza Bakari Uwase Mensah Habimana Diallo Kamau Ndayisaba Tesfaye Karenzi)
  local MAX=200
  while true; do
    ask "How many students in the new roster (1-$MAX)" n
    if is_int "$n" && (( n>=1 && n<=MAX )); then break; fi
    warn "Please enter a whole number between 1 and $MAX."
  done
  { echo "Email,Names,Attendance Count,Absence Count"
    for ((i=0; i<n; i++)); do
      first="${FIRST[i % ${#FIRST[@]}]}"; last="${LAST[(i*5 + i/${#FIRST[@]}) % ${#LAST[@]}]}"
      local tag=""; (( i >= ${#FIRST[@]} )) && tag=$((i/${#FIRST[@]}+1))
      email="$(echo "${first}.${last}${tag}" | tr '[:upper:]' '[:lower:]')@example.com"
      echo "${email},${first} ${last},0,0"
    done
  } > "$file" || fail_deploy "Couldn't write the roster."
  SESSIONS=1
  ok "Generated a fresh roster of $n student(s), all starting at 0 / 0"
}

update_thresholds() {
  local cfg="$1" w f
  say
  if ! yes_no "Would you like to change the attendance alert thresholds?" n; then
    note "Keeping the defaults (warning 75%, failure 50%)."; return
  fi
  while true; do
    ask "Warning threshold %" w 75
    ask "Failure threshold %" f 50
    if ! is_int "$w" || ! is_int "$f"; then warn "Both values need to be whole numbers (digits only). Let's try again."; continue; fi
    if (( w>100 || f>100 )); then warn "Percentages can't be above 100."; continue; fi
    if (( f >= w )); then warn "Failure ($f) should be lower than warning ($w) - otherwise nobody gets a gentle heads-up first."; continue; fi
    break
  done
  sed -i.bak -e "s/\(\"warning\"[[:space:]]*:[[:space:]]*\)[0-9][0-9]*/\1${w}/" \
             -e "s/\(\"failure\"[[:space:]]*:[[:space:]]*\)[0-9][0-9]*/\1${f}/" "$cfg" \
    || fail_deploy "Couldn't update config.json."
  rm -f "$cfg.bak"
  chmod 600 "$cfg"
  ok "Thresholds updated: warning=$w, failure=$f"
}

do_deploy() {
  head1 "🌱  Deploying a new Attendance Tracker"
  preflight

  head1 "Step 2 · Naming your project"
  pick_name "${1-}"

  if [[ -e "$PROJECT_DIR" ]]; then
    warn "$PROJECT_DIR already exists."
    if yes_no "Replace it with a fresh copy? (the old one will be deleted)" n; then
      rm -rf "$PROJECT_DIR" || { oops "Couldn't remove the old folder (permission denied?)."; exit 1; }
      ok "Old folder removed"
    else
      say "Understood - I've left it exactly as it was. Choose another name next time."; exit 0
    fi
  fi

  # From here on, an interrupt means "archive + clean up"
  DEPLOYING=1
  trap 'on_interrupt "Ctrl+C"' INT
  trap 'on_interrupt "Ctrl+Z"' TSTP

  head1 "Step 3 · Building the folders"
  mkdir "$PROJECT_DIR" 2>/dev/null || fail_deploy "Couldn't create $PROJECT_DIR."
  CREATED_BY_US=1
  mkdir "$PROJECT_DIR/Helpers" "$PROJECT_DIR/reports" 2>/dev/null || fail_deploy "Couldn't create the subfolders."
  ok "Created $PROJECT_DIR/ with Helpers/ and reports/"

  head1 "Step 4 · Placing the files"
  cp "$TEMPLATES/attendance_checker.py" "$PROJECT_DIR/attendance_checker.py" || fail_deploy "Couldn't copy attendance_checker.py."
  cp "$TEMPLATES/config.json" "$PROJECT_DIR/Helpers/config.json"             || fail_deploy "Couldn't copy config.json."
  ok "attendance_checker.py and config.json copied (unmodified)"

  say; say "How would you like to build the class roster?"
  say "   A) Copy students from the sample template"
  say "   B) Generate a brand-new roster (everyone starts at zero)"
  local choice SESSIONS=5
  while true; do
    ask "Your choice (A/B)" choice
    case "${choice^^}" in
      A) build_roster_template "$PROJECT_DIR/Helpers/assets.csv"; break ;;
      B) build_roster_fresh    "$PROJECT_DIR/Helpers/assets.csv"; break ;;
      *) warn "Please type A or B." ;;
    esac
  done
  # total_sessions = prior sessions + today's  (4+1 for the sample, 0+1 for fresh)
  sed -i.bak "s/\(\"total_sessions\"[[:space:]]*:[[:space:]]*\)[0-9][0-9]*/\1${SESSIONS}/" "$PROJECT_DIR/Helpers/config.json" \
    || fail_deploy "Couldn't set total_sessions."
  rm -f "$PROJECT_DIR/Helpers/config.json.bak"
  ok "total_sessions set to $SESSIONS to match the roster"

  head1 "Step 5 · Setting permissions"
  chmod +x "$PROJECT_DIR/attendance_checker.py" || fail_deploy "chmod +x failed."
  chmod 600 "$PROJECT_DIR/Helpers/config.json"  || fail_deploy "chmod 600 failed."
  ok "attendance_checker.py → $(stat -c %A "$PROJECT_DIR/attendance_checker.py" 2>/dev/null || ls -l "$PROJECT_DIR/attendance_checker.py" | cut -c1-10) (executable)"
  ok "Helpers/config.json  → $(stat -c %A "$PROJECT_DIR/Helpers/config.json" 2>/dev/null || ls -l "$PROJECT_DIR/Helpers/config.json" | cut -c1-10) (owner read/write only)"

  head1 "Step 6 · Alert thresholds"
  update_thresholds "$PROJECT_DIR/Helpers/config.json"

  # Setup finished: release the guards before the interactive session
  trap - INT TSTP; DEPLOYING=0
  head1 "Step 7 · Verifying with a first launch"
  say "Everything is in place. I'll start the app now - a clean start proves it all fits together."
  say "(You can mark a few students, or press Ctrl+C to leave once it has started.)"; say
  do_run_in "$PROJECT_DIR"
  say; ok "Deployment complete. Next time: './deploy_agent.sh run $PROJECT_NAME'"
}

# =============================================================================
# FEATURE 2 - RUN
# =============================================================================
do_run_in() {
  ( cd "$1" && python3 attendance_checker.py )
  local rc=$?
  if (( rc != 0 )); then warn "The app finished with exit code $rc."; fi
  return 0
}
do_run() {
  head1 "▶  Running the Attendance Tracker"
  command -v python3 >/dev/null 2>&1 || { oops "python3 isn't installed."; exit 1; }
  find_existing "${1-}" || exit 1
  do_run_in "$PROJECT_DIR"
  say; note "Done. Run './deploy_agent.sh archive $PROJECT_NAME' to keep a copy of this session's logs."
}

# =============================================================================
# FEATURE 3 - ARCHIVE
# =============================================================================
do_archive() {
  head1 "📦  Archiving session logs"
  find_existing "${1-}" || exit 1
  local stamp; stamp="$(date +%Y%m%d_%H%M%S)"
  local archived=0 kind src dest
  for kind in attendance absent; do
    src="$PROJECT_DIR/reports/$kind.log"
    dest="$PROJECT_DIR/archives/$kind/${kind}_${stamp}.log"
    if [[ -f "$src" ]]; then
      if mkdir -p "$PROJECT_DIR/archives/$kind" && cp -p "$src" "$dest"; then
        ok "$kind.log archived → $dest"; ((archived++))
      else
        oops "Couldn't archive $kind.log (permission problem?)."
      fi
    else
      note "No $kind.log this time$( [[ $kind == absent ]] && echo ' - lovely, that usually means full attendance' ). Skipped."
    fi
  done
  (( archived == 0 )) && warn "Nothing to archive yet. Run a marking session first." \
                       || { say; note "Originals stay in reports/ - archives are copies, so nothing is ever lost."; }
}

# =============================================================================
# MENU / FLAGS
# =============================================================================
usage() { sed -n '3,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

menu() {
  say "${C_B}Attendance Tracker · Deploy Agent${C_OFF}"
  say "What would you like to do?"
  say "   1) Deploy a new project"
  say "   2) Run the tracker"
  say "   3) Archive the logs"
  say "   4) Leave"
  local c
  while true; do
    ask "Choose 1-4" c
    case "$c" in 1) do_deploy; return ;; 2) do_run; return ;; 3) do_archive; return ;;
      4|q|Q) say "Take care!"; return ;; *) warn "Please pick a number from 1 to 4." ;; esac
  done
}

case "${1-}" in
  "")                 menu ;;
  deploy|-d|--deploy) do_deploy  "${2-}" ;;
  run|-r|--run)       do_run     "${2-}" ;;
  archive|-a|--archive) do_archive "${2-}" ;;
  help|-h|--help)     usage ;;
  *) oops "I don't recognise '$1'."; usage; exit 1 ;;
esac
