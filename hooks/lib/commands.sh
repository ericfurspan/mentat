# shellcheck shell=bash
# shellcheck disable=SC2034 # commands, words and the others are read by the hooks.
# Sourced by hooks that act on the real commands of a Bash tool call, so text inside
# quotes, a comment or a heredoc body is never taken for a command.
#
# shell_commands <text>: sets $commands, one line per simple command: those in $(...),
# backticks and <(...) too. Words are split by \037 with their quotes and backslashes
# off; a word longer than 4096 characters is cut there. Each redirect is a word \035<op>
# (with its file descriptor, as in \0352>) followed by its target; a heredoc's target is
# its delimiter. Returns non-zero when the split fails.
# split_words <line>: sets words, n (arguments and command words), and redir_op and
# redir_to (the redirects, in order).
# command_at: sets ci, the index in words of the command word: past assignments, { } ( !,
# shell keywords and the wrappers env, sudo, command, builtin, exec, nohup, time, nice,
# timeout and xargs with their options. ci is n when there is none.
# gh_at: when the command word is gh, sets gi to its first word that is no flag (-R
# and --repo take a value); returns 1 when the command is not gh. gh_skip moves gi past
# flags from where it is.
# hooks_key <key>: the git config key is core.hooksPath, in any case.
# config_hooks_write <index>: the git config arguments from words[index] on set, unset,
# add or replace core.hooksPath; a read of it returns 1.
# Hooks are nets for common mistakes, not a security boundary.

# The splitter reads the text one character at a time, so a long quoted body costs
# linear time; it keeps state in globals and saves it around each substitution.
# shellcheck disable=SC2016 # awk code, not shell expansions.
shell_split_awk='
BEGIN { US = "\037"; OP = "\035"; CAP = 4096; SQ = "\047"; L = ""; NW = 0; W = ""; WL = 0; IW = 0; WQ = 0; nh = 0; hf = 1 }
{ t = t (NR > 1 ? "\n" : "") $0 }
END { n = split(t, c, ""); i = 1; parse(""); endcmd() }
function add(s) { if (WL < CAP) { W = W s; WL += length(s) } IW = 1 }
function ch1(x) { return x == "\n" ? " " : x }
function endword() { if (IW) { L = (NW ? L US : "") W; NW++ } W = ""; WL = 0; IW = 0; WQ = 0 }
function addop(op) { endword(); L = (NW ? L US : "") OP op; NW++ }
function endcmd() { endword(); if (NW) print L; L = ""; NW = 0 }
function parse(stop,    ch, depth) {
  depth = 0
  while (i <= n) {
    ch = c[i]
    if (stop == "`" && ch == "`") { i++; return }
    if (stop == ")" && ch == ")" && depth == 0) { i++; return }
    if (ch == " " || ch == "\t") { endword(); i++; continue }
    if (ch == "\n") { endcmd(); i++; heredocs(); continue }
    if (ch == "#" && !IW) { while (i <= n && c[i] != "\n") i++; continue }
    if (ch == ";") { endcmd(); i++; continue }
    if (ch == "|") { endcmd(); i++; if (c[i] == "|" || c[i] == "&") i++; continue }
    if (ch == "&") {
      if (c[i + 1] == ">") { endword(); i += 2; if (c[i] == ">") { i++; addop("&>>") } else addop("&>"); continue }
      endcmd(); i++; if (c[i] == "&") i++; continue
    }
    if (ch == ">" || ch == "<") { redirect(); continue }
    if (ch == "(") {
      if (IW && W ~ /=$/) { add("("); i++; raw("(", ")"); continue }
      if (!IW) { endcmd(); depth++; i++; continue }
      add("("); i++; continue
    }
    if (ch == ")") { endcmd(); if (depth > 0) depth--; i++; continue }
    if (ch == SQ) { IW = 1; WQ = 1; i++; while (i <= n && c[i] != SQ) { add(ch1(c[i])); i++ } i++; continue }
    if (ch == "\"") { dquote(); continue }
    if (ch == "\\") { if (c[i + 1] == "\n") { i += 2; continue } WQ = 1; add(c[i + 1]); i += 2; continue }
    if (ch == "$") { dollar(); continue }
    if (ch == "`") { add("`"); i++; subst("`"); continue }
    add(ch); i++
  }
}
function dquote(    ch, nx) {
  IW = 1; WQ = 1; i++
  while (i <= n && c[i] != "\"") {
    ch = c[i]
    if (ch == "\\") {
      nx = c[i + 1]
      if (nx == "\n") { i += 2; continue }
      if (nx == "$" || nx == "`" || nx == "\"" || nx == "\\") add(nx); else add("\\" ch1(nx))
      i += 2; continue
    }
    if (ch == "$") { dollar(); continue }
    if (ch == "`") { add("`"); i++; subst("`"); continue }
    add(ch1(ch)); i++
  }
  i++
}
function dollar() {
  if (c[i + 1] == "(" && c[i + 2] == "(") { add("$(("); i += 3; raw("(", ")"); if (c[i] == ")") { add(")"); i++ } return }
  if (c[i + 1] == "(") { add("$("); i += 2; subst(")"); return }
  if (c[i + 1] == "{") { add("${"); i += 2; raw("{", "}"); return }
  add("$"); i++
}
# raw <open> <close>: adds the text up to the matching close, which it includes.
function raw(o, cl,    depth) {
  depth = 1
  while (i <= n) {
    if (c[i] == o) depth++
    else if (c[i] == cl && --depth == 0) { add(cl); i++; return }
    add(ch1(c[i])); i++
  }
}
# subst <stop>: emits the commands inside a substitution, adding its text to the word.
function subst(stop,    sL, sNW, sW, sWL, sIW, sWQ, start, k, s, m) {
  sL = L; sNW = NW; sW = W; sWL = WL; sIW = IW; sWQ = WQ
  L = ""; NW = 0; W = ""; WL = 0; IW = 0; WQ = 0
  start = i
  parse(stop)
  endcmd()
  L = sL; NW = sNW; W = sW; WL = sWL; IW = 1; WQ = sWQ
  s = ""; m = 0
  for (k = start; k < i && m < CAP; k++) { s = s ch1(c[k]); m++ }
  add(s)
}
function redirect(    fd, op, strip) {
  fd = ""
  if (IW && !WQ && W ~ /^[0-9]+$/) { fd = W; W = ""; WL = 0; IW = 0 } else endword()
  if (c[i] == "<") {
    if (c[i + 1] == "<" && c[i + 2] == "<") { op = "<<<"; i += 3 }
    else if (c[i + 1] == "<") { i += 2; strip = 0; if (c[i] == "-") { strip = 1; i++ } heredoc(fd, strip); return }
    else if (c[i + 1] == ">") { op = "<>"; i += 2 }
    else if (c[i + 1] == "&") { op = "<&"; i += 2 }
    else if (c[i + 1] == "(") { add("<("); i += 2; subst(")"); return }
    else { op = "<"; i++ }
  } else {
    if (c[i + 1] == ">") { op = ">>"; i += 2 }
    else if (c[i + 1] == "|") { op = ">|"; i += 2 }
    else if (c[i + 1] == "&") { op = ">&"; i += 2 }
    else if (c[i + 1] == "(") { add(">("); i += 2; subst(")"); return }
    else { op = ">"; i++ }
  }
  addop(fd op)
}
# heredoc: reads the delimiter (quotes off) and queues its body to skip at the next newline.
function heredoc(fd, strip,    d, ch) {
  addop(fd "<<")
  while (c[i] == " " || c[i] == "\t") i++
  d = ""
  while (i <= n) {
    ch = c[i]
    if (ch == " " || ch == "\t" || ch == "\n" || ch == ";" || ch == "|" || ch == "&" || ch == "<" || ch == ">" || ch == "(" || ch == ")") break
    if (ch == SQ) { i++; while (i <= n && c[i] != SQ) { d = d c[i]; i++ } i++; continue }
    if (ch == "\"") { i++; while (i <= n && c[i] != "\"") { d = d c[i]; i++ } i++; continue }
    if (ch == "\\") { d = d c[i + 1]; i += 2; continue }
    d = d ch; i++
  }
  L = (NW ? L US : "") d; NW++
  hd[++nh] = d; hs[nh] = strip
}
function heredocs(    e, j, line, k) {
  while (hf <= nh) {
    while (i <= n) {
      e = i; while (e <= n && c[e] != "\n") e++
      j = i; if (hs[hf]) while (j < e && c[j] == "\t") j++
      line = ""
      if (e - j == length(hd[hf])) for (k = j; k < e; k++) line = line c[k]
      i = e + 1
      if (e - j == length(hd[hf]) && line == hd[hf]) break
    }
    hf++
  }
}
'

shell_commands() {
  commands=$(printf '%s' "$1" | LC_ALL=C awk "$shell_split_awk")
}

split_words() {
  local f k=0 all
  words=() redir_op=() redir_to=()
  IFS=$'\037' read -r -a all <<<"$1"
  while [ "$k" -lt "${#all[@]}" ]; do
    f=${all[k]}
    case "$f" in
      $'\035'*)
        redir_op+=("${f#?}")
        redir_to+=("${all[k + 1]:-}")
        k=$((k + 2))
        ;;
      *) words+=("$f"); k=$((k + 1)) ;;
    esac
  done
  n=${#words[@]}
}

command_at() {
  local w wrap=""
  ci=0
  while [ "$ci" -lt "$n" ]; do
    w=${words[ci]}
    case "$wrap" in
      env)
        case "$w" in
          -u | -C | -S | -P | --unset | --chdir | --split-string) ci=$((ci + 2)); continue ;;
          -* | *=*) ci=$((ci + 1)); continue ;;
        esac
        ;;
      sudo)
        case "$w" in
          -u | -g | -C | -D | -h | -p | -r | -t | -U | -T) ci=$((ci + 2)); continue ;;
          -*) ci=$((ci + 1)); continue ;;
        esac
        ;;
      nice)
        case "$w" in -n) ci=$((ci + 2)); continue ;; -*) ci=$((ci + 1)); continue ;; esac
        ;;
      timeout)
        case "$w" in
          -s | -k | --signal | --kill-after) ci=$((ci + 2)); continue ;;
          -*) ci=$((ci + 1)); continue ;;
          *) ci=$((ci + 1)) wrap=""; continue ;;
        esac
        ;;
      xargs)
        case "$w" in
          -I | -J | -L | -n | -P | -R | -s | -S | -E | -d | -a) ci=$((ci + 2)); continue ;;
          -*) ci=$((ci + 1)); continue ;;
        esac
        ;;
      exec)
        case "$w" in -a) ci=$((ci + 2)); continue ;; -*) ci=$((ci + 1)); continue ;; esac
        ;;
      other)
        case "$w" in -*) ci=$((ci + 1)); continue ;; esac
        ;;
    esac
    wrap=""
    case "$w" in
      "{" | "}" | "(" | "!" | if | then | else | elif | fi | do | done | while | until) ;;
      env | sudo | nice | timeout | xargs | exec) wrap=$w ;;
      command | builtin | nohup | time) wrap=other ;;
      *)
        [[ $w =~ ^[A-Za-z_][A-Za-z0-9_]*\+?= ]] || return 0
        ;;
    esac
    ci=$((ci + 1))
  done
}

gh_at() {
  case "${words[ci]:-}" in gh | */gh) ;; *) return 1 ;; esac
  gi=$((ci + 1))
  gh_skip
}

gh_skip() {
  while [ "$gi" -lt "$n" ]; do
    case "${words[gi]}" in
      -R | --repo) gi=$((gi + 2)) ;;
      -*) gi=$((gi + 1)) ;;
      *) return 0 ;;
    esac
  done
}

hooks_key() {
  case "$1" in [Cc][Oo][Rr][Ee].[Hh][Oo][Oo][Kk][Ss][Pp][Aa][Tt][Hh]) return 0 ;; esac
  return 1
}

config_hooks_write() {
  local k=$1 w hooks="" read="" write="" count=0
  while [ "$k" -lt "$n" ]; do
    w=${words[k]}
    case "$w" in
      -f | --file | --blob | --type | --default | --comment) k=$((k + 1)) ;;
      --get | --get-all | --get-regexp | --get-urlmatch | --get-color | --get-colorbool | -l | --list | get | list) read=1 ;;
      --unset | --unset-all | --add | --replace-all | set | unset) write=1 ;;
      -*) ;;
      *)
        count=$((count + 1))
        if hooks_key "${w%%=*}"; then hooks=1; fi
        ;;
    esac
    k=$((k + 1))
  done
  [ -n "$hooks" ] && [ -z "$read" ] && { [ -n "$write" ] || [ "$count" -ge 2 ]; }
}
