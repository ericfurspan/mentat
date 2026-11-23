# The glossary check's matcher, run by tests/glossary-check.sh, which says the format it reads.
# Usage: awk -v G=<glossary> -f tests/glossary-check.awk <glossary> [<checked file>...]
# The glossary is always the first file. Prints PASS/FAIL lines; exits 1 on any FAIL.

function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
# Lowercase; every run of characters other than letters, digits and the | separator becomes one space.
function norm(s) { s = tolower(s); gsub(/[^a-z0-9|]+/, " ", s); return trim(s) }
function bad(msg) { printf "FAIL: glossary %s\n", msg; failed = 1 }
# forms(A, k, t, whole): A[k, 1..n] holds the forms of phrase t that match; returns n.
function forms(A, k, t, whole,   n, pre, last, stem, c) {
  n = 0
  A[k, ++n] = t
  if (whole) return n
  pre = ""; last = t
  if (match(t, / [^ ]+$/)) { pre = substr(t, 1, RSTART); last = substr(t, RSTART + 1) }
  A[k, ++n] = pre last "s"; A[k, ++n] = pre last "es"
  A[k, ++n] = pre last "ed"; A[k, ++n] = pre last "d"; A[k, ++n] = pre last "ing"
  if (last ~ /e$/) { stem = substr(last, 1, length(last) - 1); A[k, ++n] = pre stem "ing" }
  if (last ~ /[^aeiou]y$/) { stem = substr(last, 1, length(last) - 1); A[k, ++n] = pre stem "ies"; A[k, ++n] = pre stem "ied" }
  if (last ~ /[aeiou][bdgklmnprt]$/) { c = substr(last, length(last)); A[k, ++n] = pre last c "ed"; A[k, ++n] = pre last c "ing" }
  return n
}
function finish_glossary(   a, k, j, ca) {
  done_glossary = 1
  if (nt == 0) bad(G ": its Avoid lines name no words")
  for (a = 1; a <= ne; a++) {
    if (!has_avoid[a]) bad(G ": entry \"" E[a] "\" has no Avoid line")
    ca = norm(E[a])
    if (flagged[a]) FN[a] = forms(FF, a, ca, 0)
    for (k = 1; k <= nt; k++) {
      if (TE[k] == a) continue
      if (index(" " T[k] " ", " " ca " ")) {
        bad(G ": entry \"" E[a] "\" is avoided by entry \"" E[TE[k]] "\" (\"" T[k] "\")")
        continue
      }
      for (j = 1; j <= TN[k]; j++) {
        if (index(" " ca " ", " " TF[k, j] " ")) {
          bad(G ": entry \"" E[a] "\" holds \"" T[k] "\", avoided by entry \"" E[TE[k]] "\"")
          break
        }
      }
    }
  }
  if (!failed) printf "PASS: glossary %s: %d entries, %d avoided terms\n", G, ne, nt
}
function end_sentence() { if (words > 20) long++; words = 0 }
function end_file(   a, list) {
  end_sentence()
  if (hits) return
  list = ""
  for (a = 1; a <= ne; a++) if (flagged[a] && count[a]) list = list (list == "" ? "" : ", ") E[a] " " count[a]
  if (list == "") list = "none"
  printf "PASS: glossary %s: no avoided words; %d sentence(s) over 20 words; flagged: %s\n", file, long, list
}

# The glossary.
NR == FNR {
  if ($0 ~ /^## /) { ne++; E[ne] = trim(substr($0, 4)); next }
  if (ne == 0) next
  if ($0 ~ /^Avoid( \(whole phrase\))?:/) {
    whole = ($0 ~ /^Avoid \(whole phrase\):/)
    v = $0; sub(/^[^:]*:/, "", v); v = trim(v)
    has_avoid[ne] = 1
    if (tolower(v) == "none") next
    np = split(v, parts, ",")
    for (i = 1; i <= np; i++) {
      p = norm(parts[i])
      if (p == "") continue
      nt++; T[nt] = p; TE[nt] = ne; TN[nt] = forms(TF, nt, p, whole)
    }
    next
  }
  if ($0 ~ /^Ambiguous:/) flagged[ne] = 1
  next
}

# A checked file.
{
  if (FNR == 1) {
    if (!done_glossary) finish_glossary()
    if (file != "") end_file()
    file = FILENAME; hits = 0; long = 0; words = 0; fence = 0; front = 0
    for (a = 1; a <= ne; a++) count[a] = 0
    if ($0 == "---") { front = 1; next }
  }
  line = $0
  if (front) {
    if (line == "---") { front = 0; next }
    if (line !~ /^description:/) next
    sub(/^description:/, "", line)
  }
  if (line ~ /^[ \t]*(```|~~~)/) { end_sentence(); fence = !fence; next }
  if (fence) next

  # Skipped: code spans, link targets, URLs, paths and file names. Each becomes a | separator,
  # so no phrase runs across it.
  gsub(/`[^`]*`/, " | ", line)
  gsub(/\]\([^)]*\)/, "] | ", line)
  gsub(/[A-Za-z][A-Za-z0-9+.-]*:\/\/[^ \t)]*/, " | ", line)
  gsub(/[^ \t()"'`]*\/[^ \t()"'`]*/, " | ", line)
  gsub(/[A-Za-z0-9_.-]*[A-Za-z0-9_]\.(md|sh|json|yml|yaml|txt|toml|js|ts|py)/, " | ", line)

  # Sentences: a blank line, a heading, a table row or a list item starts a new one, and a
  # word ending in ., ! or ? ends one. Only words holding a letter or digit count.
  if (line ~ /^[ \t]*$/) end_sentence()
  else {
    unit = (line ~ /^#/ || line ~ /^[ \t]*\|/)
    if (unit) end_sentence()
    if (line ~ /^[ \t]*([-*+]|[0-9]+[.)])[ \t]/) { end_sentence(); sub(/^[ \t]*([-*+]|[0-9]+[.)])[ \t]+/, "", line) }
    nw = split(line, toks, /[ \t]+/)
    for (i = 1; i <= nw; i++) {
      if (toks[i] ~ /[A-Za-z0-9]/) words++
      if (toks[i] ~ /[.!?][)"'*_]*$/) end_sentence()
    }
    if (unit) end_sentence()
  }

  L = " " norm(line) " "
  for (k = 1; k <= nt; k++) {
    for (j = 1; j <= TN[k]; j++) {
      if (index(L, " " TF[k, j] " ")) {
        bad(file ":" FNR ": \"" T[k] "\" is avoided by entry \"" E[TE[k]] "\"")
        hits++
        break
      }
    }
  }
  for (a = 1; a <= ne; a++) {
    if (!flagged[a]) continue
    for (j = 1; j <= FN[a]; j++) {
      s = L; f = " " FF[a, j] " "
      while ((p = index(s, f)) > 0) { count[a]++; s = substr(s, p + length(f) - 1) }
    }
  }
}

END {
  if (!done_glossary) finish_glossary()
  if (file != "") end_file()
  exit failed
}
