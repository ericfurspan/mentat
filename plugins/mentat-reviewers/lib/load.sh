# shellcheck shell=bash
# shellcheck disable=SC2154 # entry, via, core_libs, module_libs and module are the entry's
# Sourced first by each entry in this module's bin/: loads core's libraries named in
# core_libs from MENTAT_ROOT, the folder of Mentat's bin/mentat, which sets it when it
# hands a command over, then this module's named in module_libs. Without MENTAT_ROOT it
# says what it needs and exits 64.
if [ -z "${MENTAT_ROOT:-}" ]; then
  printf '%s: needs MENTAT_ROOT, the folder holding Mentat'"'"'s bin/mentat and lib/; run it as %s, which sets it\n' "$entry" "$via" >&2
  exit 64
fi
for f in $core_libs; do
  f="$MENTAT_ROOT/lib/$f.sh"
  [ -f "$f" ] || { printf 'mentat: missing %s\n' "$f" >&2; exit 1; }
  # shellcheck source=/dev/null
  . "$f" || exit 1
done
for f in $module_libs; do
  f="$module/lib/$f.sh"
  [ -f "$f" ] || { printf 'mentat: missing %s\n' "$f" >&2; exit 1; }
  # shellcheck source=/dev/null
  . "$f" || exit 1
done
