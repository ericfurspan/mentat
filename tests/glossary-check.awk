# The glossary check's matcher, run by tests/glossary-check.sh, which says the format it reads.
# Usage: awk -v G=<glossary> -f tests/glossary-check.awk <glossary> [<checked file>...]
# The glossary is always the first file. Prints PASS/FAIL lines; exits 1 on any FAIL.

function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
# Lowercase; every run of characters other than letters, digits and the | separator becomes one space.
function norm(s) { s = tolower(s); gsub(/[^a-z0-9|]+/, " ", s); return trim(s) }
# Lowercase; tabs become spaces and every run of spaces one space. A whole phrase matches in this.
function words_of(s) { s = tolower(s); gsub(/[ \t]+/, " ", s); return trim(s) }
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
# close_run(s, n): where in s the first run of exactly n backticks starts, or 0.
function close_run(s, n,   off) {
  off = 0
  while (match(s, /`+/)) {
    if (RLENGTH == n) return off + RSTART
    off += RSTART + RLENGTH - 1; s = substr(s, RSTART + RLENGTH)
  }
  return 0
}
# spans(s): s with each code span a " | " separator. As in CommonMark, a span opens at a run of
# backticks and closes at the next run of the same length; a run with no such close stays text.
function spans(s,   out, at, n, rest, p) {
  out = ""
  while (match(s, /`+/)) {
    at = RSTART; n = RLENGTH; rest = substr(s, at + n)
    out = out substr(s, 1, at - 1)
    if ((p = close_run(rest, n)) > 0) { out = out " | "; s = substr(rest, p + n) }
    else { out = out substr(s, at, n); s = rest }
  }
  return out s
}
# is_path(t): whether token t, which holds a /, reads as a path rather than words joined by a
# slash: past any brackets, emphasis and closing punctuation around it, it starts with /, ./, ../
# or ~, ends with /, holds a glob * beside a /, or ends in a file extension.
function is_path(t) {
  sub(/^[\[*_<]+/, "", t); sub(/[\]*_>.,;:!?]+$/, "", t)
  return t ~ /^(\/|\.\.?\/|~)/ || t ~ /\/$/ || t ~ /\/\*|\*\// || t ~ /\.[A-Za-z][A-Za-z0-9]*$/
}
# paths(s): s with each path a " | " separator; words joined by a slash stay prose.
function paths(s,   out, t) {
  out = ""
  while (match(s, /[^ \t()"'`]*\/[^ \t()"'`]*/)) {
    t = substr(s, RSTART, RLENGTH)
    out = out substr(s, 1, RSTART - 1)
    s = substr(s, RSTART + RLENGTH)
    out = out (is_path(t) ? " | " : t)
  }
  return out s
}
function end_sentence() { if (words > 20) long++; words = 0 }
# A paragraph is consecutive prose lines; PB holds their normalized text and RB their words_of
# text, each with one space before each line; PS[i] and WS[i] are the lengths of PB and RB before
# line i, and PL[i] its line number.
function add_line(t, r) {
  if (t == "" && r == "") return
  if (pn == 0) { PB = " "; RB = " " }
  pn++; PS[pn] = length(PB); WS[pn] = length(RB); PL[pn] = FNR; PB = PB t " "; RB = RB r " "
}
# line_at(p, O): the paragraph line holding the text that starts after position p of the buffer
# whose line offsets O holds.
function line_at(p, O,   i) { for (i = pn; i > 1; i--) if (O[i] <= p) return i; return 1 }
# joins(c): whether character c joins the words beside it, so a whole phrase cannot end there.
function joins(c) { return c ~ /[a-z0-9-]/ }
# flush(): checks the paragraph, reporting each avoided term once per line it starts on.
function flush(   k, j, i, s, f, p, q, off, hk, a) {
  if (pn == 0) return
  for (k = 1; k <= nt; k++) {
    if (WH[k]) {
      # A whole phrase: its words separated by whitespace, with no letter, digit or hyphen on
      # either side.
      off = 0
      while ((p = index(substr(RB, off + 1), W[k])) > 0) {
        q = off + p
        if (!joins(substr(RB, q - 1, 1)) && !joins(substr(RB, q + length(W[k]), 1))) hk[k, line_at(q - 1, WS)] = 1
        off = q
      }
      continue
    }
    for (j = 1; j <= TN[k]; j++) {
      s = PB; f = " " TF[k, j] " "; off = 0
      while ((p = index(s, f)) > 0) {
        hk[k, line_at(off + p, PS)] = 1
        off += p + length(f) - 2; s = substr(s, p + length(f) - 1)
      }
    }
  }
  for (i = 1; i <= pn; i++) {
    for (k = 1; k <= nt; k++) {
      if (!((k, i) in hk)) continue
      bad(file ":" PL[i] ": \"" T[k] "\" is avoided by entry \"" E[TE[k]] "\"")
      hits++
    }
  }
  for (a = 1; a <= ne; a++) {
    if (!flagged[a]) continue
    for (j = 1; j <= FN[a]; j++) {
      s = PB; f = " " FF[a, j] " "
      while ((p = index(s, f)) > 0) { count[a]++; s = substr(s, p + length(f) - 1) }
    }
  }
  pn = 0
}
function end_file(   a, list) {
  flush()
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
      if (whole) { WH[nt] = 1; W[nt] = words_of(parts[i]) }
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
    file = FILENAME; hits = 0; long = 0; words = 0; fc = ""; front = 0
    for (a = 1; a <= ne; a++) count[a] = 0
    if ($0 == "---") { front = 1; next }
  }
  line = $0; desc = 0
  if (front) {
    if (line == "---") { front = 0; next }
    if (line !~ /^description:/) next
    sub(/^description:/, "", line); desc = 1
  }
  # A fence: a run of three or more backticks or tildes, a backtick one with no backtick after it.
  # It closes only at a line holding just a run of its opening character at least as long.
  if (line ~ /^[ \t]*(```|~~~)/) {
    s = line; sub(/^[ \t]+/, "", s); c = substr(s, 1, 1)
    if (c == "`") match(s, /^`+/); else match(s, /^~+/)
    n = RLENGTH; rest = substr(s, n + 1)
    if (fc == "" && !(c == "`" && index(rest, "`"))) { end_sentence(); flush(); fc = c; fl = n; next }
    if (fc != "" && c == fc && n >= fl && rest ~ /^[ \t]*$/) { fc = ""; next }
  }
  if (fc != "") next
  # A heading or table row, read before the skips below can make a line start with |.
  unit = (line ~ /^#/ || line ~ /^[ \t]*\|/)

  # Skipped: code spans, link targets, URLs, paths and file names. Each becomes a | separator,
  # so no phrase runs across it.
  line = spans(line)
  gsub(/\]\([^)]*\)/, "] | ", line)
  gsub(/[A-Za-z][A-Za-z0-9+.-]*:\/\/[^ \t)]*/, " | ", line)
  line = paths(line)
  gsub(/[A-Za-z0-9_.-]*[A-Za-z0-9_]\.(md|sh|json|yml|yaml|txt|toml|js|ts|py)/, " | ", line)

  # Sentences: a blank line, a heading, a table row or a list item starts a new one, and a
  # word ending in ., ! or ? ends one. Only words holding a letter or digit count.
  # Paragraphs: a blank line, a fence or a list item starts a new one, and a heading, a table row
  # and the description are each one on their own. Avoided terms match within a paragraph.
  if (line ~ /^[ \t]*$/) { end_sentence(); flush(); next }
  if (unit) end_sentence()
  if (unit || desc) flush()
  if (line ~ /^[ \t]*([-*+]|[0-9]+[.)])[ \t]/) { end_sentence(); flush(); sub(/^[ \t]*([-*+]|[0-9]+[.)])[ \t]+/, "", line) }
  nw = split(line, toks, /[ \t]+/)
  for (i = 1; i <= nw; i++) {
    if (toks[i] ~ /[A-Za-z0-9]/) words++
    if (toks[i] ~ /[.!?][)"'*_]*$/) end_sentence()
  }
  if (unit) end_sentence()
  add_line(norm(line), words_of(line))
  if (unit || desc) flush()
}

END {
  if (!done_glossary) finish_glossary()
  if (file != "") end_file()
  exit failed
}
