#!/usr/bin/env bash
# Fusion Старт 1.1: ставит базовый набор Claude Code скриптом хука SessionStart.
#
# Зачем скрипт, а не команды Claude: в Claude Desktop команды Claude идут в песочнице,
# и она запрещает писать в ~/.claude (навыки и плагины) и в ~/.claude.json (MCP).
# Хуки приложение выполняет вне песочницы (code.claude.com/docs/en/sandboxing).
#
# Режимы:
#   --notice  быстрый синхронный хук: если набор нужен, говорит об этом. Ничего не ставит.
#   --auto    асинхронный хук (async: true): ставит набор в фоне и сообщает Claude на следующем ходу.
#   --run     установка в этом процессе (ручной запуск из терминала).
#
# Принципы: качаем у авторов, версии и коммиты закреплены, чужой код в репозиторий не копируем,
# «уже стоит» не трогаем, ключей и паролей не спрашиваем, ничего никуда не отправляем.
# Отказаться от набора: создать файл ~/.fusion-start/off (тогда хук молчит).

case "$(uname -s 2>/dev/null)" in Darwin|Linux|MINGW*|MSYS*|CYGWIN*) ;; *) exit 0 ;; esac
umask 077

KIT_VERSION="1.1.0"
STATE_DIR="$HOME/.fusion-start"
STATE="$STATE_DIR/nabor.json"
LOCK="$STATE_DIR/nabor.lock"
LOG="$STATE_DIR/nabor.log"

# --- закреплённые источники (проверены 10.11.2026) ---
SKILLS_CLI="skills@1.7.6"
PLAYWRIGHT_MCP="@playwright/mcp@0.0.84"
CONTEXT7_MCP="@upstash/context7-mcp@4.5.1" # upstash/context7 (MIT): свежая документация библиотек, без ключа
HYPERFRAMES_SHA="b4cc674f7f312e77ded32e0b53006cc0bad6723b" # heygen-com/hyperframes, тег v0.9.19
REMOTION_SHA="c7cb2fdcacd134fb2ccb9b7a44f9ffa44e467271"    # remotion-dev/skills
GSAP_SHA="aed9cfd3277740755f6bfc1155c7aa645403b760"        # greensock/gsap-skills (MIT)
ANTHROPIC_SKILLS_SHA="2c5958ecac7cee2b583967a2c4981d0f4a75c579" # anthropics/skills: pdf, docx, pptx, xlsx
MCP_PREFIX="$STATE_DIR/mcp" # сюда ставится Playwright MCP, чтобы Claude запускал его по абсолютному пути
AR_URL="https://github.com/Panniantong/Agent-Reach/releases/download/v1.6.1/agent-reach.zip"
AR_SHA256="51443d733bcb26064262442083a8f8abf6ba5e3e7df54beebafe98c88be04a60"
ECC_MARKETPLACE="affaan-m/ECC#v2.2.3"
ECC_NPM="ecc-universal@2.2.3" # официальный установщик ECC (affaan-m/ECC, MIT), режим хуков standard
CLAUDE_MEM_MARKETPLACE="thedotmack/claude-mem#v15.0.1"
GRAPHIFY_PKG="graphifyy==0.9.105" # Graphify-Labs/graphify (Apache-2.0)
CLAUDE_MEM_SHA="0e7de4ee4671ff3e5c233b721904e9eac9d61792" # коммит тега v15.0.1: тег сверяется перед установкой
ECC_SHA="c05b2d6614f62f6db0047669aa4eefb223d478f9"        # коммит тега v2.2.3
UV_VERSION="0.13.4"
UV_SH_SHA256="1f5390d273b0158bd5eaa3527ae049f3667baa881abb1e7c883dd637d84432f9"
UV_PS1_SHA256="97b4489acafc6a9b2a6529eba6ef46d8d936ed53c0a7acfd9fd5eb4927932144"

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
export DISABLE_TELEMETRY=1 DO_NOT_TRACK=1
export NPM_CONFIG_REGISTRY="https://registry.npmjs.org/" NPM_CONFIG_UPDATE_NOTIFIER=false GIT_TERMINAL_PROMPT=0

is_windows() { case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; esac; return 1; }

state_str() { sed -n "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/p" "$STATE" 2>/dev/null | head -1; }
state_num() { sed -n "s/.*\"$1\": *\([0-9][0-9]*\).*/\1/p" "$STATE" 2>/dev/null | head -1; }

write_state() { # status tries missing notes
  mkdir -p "$STATE_DIR"
  local tmp="$STATE.$$.tmp"
  printf '{"kit":"%s","status":"%s","tries":%s,"missing":"%s","notes":"%s"}\n' \
    "$KIT_VERSION" "$1" "${2:-0}" "$3" "$4" >"$tmp" && mv "$tmp" "$STATE"
}

need_install() {
  [ -f "$STATE_DIR/off" ] && return 1
  mkdir -p "$STATE_DIR" 2>/dev/null || return 1
  local status kit tries
  status="$(state_str status)"; kit="$(state_str kit)"; tries="$(state_num tries)"
  if [ "$kit" = "$KIT_VERSION" ]; then
    [ "$status" = "ok" ] && return 1
    [ "${tries:-0}" -ge 3 ] && return 1 # три попытки не вышли: дальше только вручную, без бесконечных повторов
  fi
  return 0
}

# Поля состояния попадают в контекст Claude: оставляем только буквы, цифры, пробел, дефис и подчёркивание.
clean() { printf '%s' "$1" | LC_ALL=C tr -cd 'a-zA-Z0-9 _-' | head -c 160; }

emit() { # сообщение человеку, контекст для Claude (в текстах нет кавычек и обратных косых)
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$1" "$2"
}

notice_mode() {
  need_install || return 0
  emit "Fusion Старт ставит базовый набор инструментов в фоне (5-15 минут, вводить ничего не нужно). В наборе ECC: его помощники могут отправлять выжимку разговора во внешнюю модель." "Fusion Старт: хук ставит набор $KIT_VERSION в фоне вне песочницы. Скажи человеку одной строкой, что набор ставится сам и по окончании нужно перезапустить приложение. Саму установку Bash-командами не запускай."
}

auto_mode() {
  need_install || return 0
  # замок старше 30 минут считаем брошенным; свежий — значит, установка уже идёт в другой сессии
  [ -n "$(find "$LOCK" -maxdepth 0 -mmin +30 2>/dev/null)" ] && rmdir "$LOCK" 2>/dev/null
  mkdir "$LOCK" 2>/dev/null || return 0
  : >"$LOG" 2>/dev/null
  LOCK_HELD=1 run_mode </dev/null >>"$LOG" 2>&1
  local status missing notes
  status="$(state_str status)"; missing="$(clean "$(state_str missing)")"; notes="$(clean "$(state_str notes)")"
  case "$status" in
    ok)      emit "Набор Fusion Старт поставлен. Закрой Claude полностью и открой заново, тогда всё подхватится." "Fusion Старт: установка $KIT_VERSION завершена, status ok. Заметки: ${notes:-нет}. Скажи человеку полностью перезапустить приложение (Mac: Cmd+Q). Про заметки объясни по навыку fusion-start." ;;
    partial) emit "Часть набора не поставилась: ${missing:-см. журнал}. Напиши Claude: что не встало из Fusion Старт." "Fusion Старт: установка $KIT_VERSION не дошла до конца (status partial). Не поставилось: ${missing:-неизвестно}. Заметки: ${notes:-нет}. Разбери по навыку fusion-start, журнал ~/.fusion-start/nabor.log." ;;
  esac
}

find_claude() {
  local c
  for c in "${CLAUDE_CODE_EXECPATH:-}" "$(command -v claude 2>/dev/null)" "$HOME/.local/bin/claude" "$HOME/.local/bin/claude.exe" "$HOME/.claude/local/claude" /opt/homebrew/bin/claude /usr/local/bin/claude; do
    [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return; }
  done
  ls -d "$HOME/Library/Application Support/Claude/claude-code"/*/claude.app/Contents/MacOS/claude 2>/dev/null | sort -V | tail -1
}

limited() { local sec="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$sec" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$sec" "$@"
  elif command -v perl >/dev/null 2>&1; then perl -e 'alarm shift; exec @ARGV or exit 127' "$sec" "$@"
  else "$@"; fi; }

# Тег совпадает с закреплённым коммитом? Тег можно перевесить, коммит — нет.
tag_matches() { # репозиторий тег коммит
  [ "$(limited 60 git ls-remote "https://github.com/$1.git" "refs/tags/$2^{}" 2>/dev/null | cut -f1)" = "$3" ]
}

sha256_of() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1; else sha256sum "$1" 2>/dev/null | cut -d' ' -f1; fi; }

plugin_status() { # путь-к-claude полный-id
  "$1" plugin list --json 2>/dev/null | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{const p=JSON.parse(d).find(x=>x.id===process.argv[1]);console.log(p?(p.enabled===false?"disabled":"enabled"):"absent")}catch(e){console.log("unknown")}})' "$2" 2>/dev/null
}

plugin_ready() { # claude полный-id: стоит и включён (выключенный включаем)
  local st
  st="$(plugin_status "$1" "$2")"
  case "$st" in disabled*) limited 60 "$1" plugin enable "$2" >/dev/null 2>&1; st="$(plugin_status "$1" "$2")" ;; esac
  case "$st" in enabled*) return 0 ;; esac
  return 1
}

run_mode() {
  mkdir -p "$STATE_DIR"
  local prev tries claude_bin
  prev="$(state_num tries)"; [ "$(state_str kit)" = "$KIT_VERSION" ] || prev=0
  tries=$(( ${prev:-0} + 1 ))
  if [ -z "${LOCK_HELD:-}" ] && ! mkdir "$LOCK" 2>/dev/null; then echo "установка уже идёт (замок $LOCK)"; return 0; fi
  WORK="$(mktemp -d)" || exit 1
  trap 'rm -rf "$WORK"; rmdir "$LOCK" 2>/dev/null' EXIT
  local work="$WORK"
  cd "$work" || exit 1 # npx не должен запускаться из чужой папки проекта
  : >"$work/empty-npm-config"
  local npm_global="$work/empty-npm-config"
  is_windows && command -v cygpath >/dev/null 2>&1 && npm_global="$(cygpath -m "$npm_global")"
  export NPM_CONFIG_USERCONFIG=/dev/null NPM_CONFIG_GLOBALCONFIG="$npm_global"
  # перед ECC сохраняем настройки Claude: установщик ECC дописывает в них свои хуки
  [ -f "$HOME/.claude/settings.json" ] && [ ! -f "$STATE_DIR/settings.json.before" ] && cp "$HOME/.claude/settings.json" "$STATE_DIR/settings.json.before"
  write_state installing "$tries" "" ""

  local log="$work/step.log" fails=0 missing="" notes=""
  claude_bin="$(find_claude)"

  ok()    { echo "уже стоит: $1"; }
  done_() { echo "поставил: $1"; }
  fail()  { echo "НЕ ПОСТАВИЛОСЬ: $1 ($2)"; tail -n 3 "$log" 2>/dev/null | sed 's/^/    /'; fails=$((fails+1)); missing="$missing $1"; }

  has_skill() { [ -f "$HOME/.claude/skills/$1/SKILL.md" ]; }
  mcp_names() { node -e "const fs=require('fs'),os=require('os');let n=[];try{const j=JSON.parse(fs.readFileSync(os.homedir()+'/.claude.json','utf8'));n=Object.keys(j.mcpServers||{});for(const p of Object.values(j.projects||{}))n.push(...Object.keys(p.mcpServers||{}))}catch(e){}console.log(n.join(' '))" 2>/dev/null; }
  has_mcp() { case " $(mcp_names) " in *" $1 "*) return 0;; esac; return 1; }

  # --- предварительные условия ---
  local node_ok=0 git_ok=0
  if command -v node >/dev/null 2>&1 && node -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>22||(a===22&&b>=20)?0:1)' 2>/dev/null; then node_ok=1; else notes="$notes node"; fi
  command -v git >/dev/null 2>&1 && git_ok=1 || notes="$notes git"
  [ -n "$claude_bin" ] || notes="$notes claude"

  # uv (менеджер Python-инструментов от Astral) нужен для graphify и Agent Reach: официальный установщик закреплённой версии
  if ! command -v uv >/dev/null 2>&1; then
    : >"$log"
    if is_windows; then
      curl --proto =https --tlsv1.2 -fsSL --max-time 120 -o "$work/uv-install.ps1" "https://astral.sh/uv/$UV_VERSION/install.ps1" >>"$log" 2>&1
      if [ "$(sha256_of "$work/uv-install.ps1")" = "$UV_PS1_SHA256" ]; then
        local ps1="$work/uv-install.ps1"; command -v cygpath >/dev/null 2>&1 && ps1="$(cygpath -w "$ps1")"
        limited 300 powershell -NoProfile -ExecutionPolicy ByPass -File "$ps1" >>"$log" 2>&1
      else echo "контрольная сумма установщика uv не совпала, не ставлю" >>"$log"; fi
    else
      curl --proto =https --tlsv1.2 -fsSL --max-time 120 -o "$work/uv-install.sh" "https://astral.sh/uv/$UV_VERSION/install.sh" >>"$log" 2>&1
      if [ "$(sha256_of "$work/uv-install.sh")" = "$UV_SH_SHA256" ]; then limited 300 sh "$work/uv-install.sh" >>"$log" 2>&1
      else echo "контрольная сумма установщика uv не совпала, не ставлю" >>"$log"; fi
    fi
    command -v uv >/dev/null 2>&1 && echo "поставил: uv" || { echo "uv не поставился (см. журнал)"; notes="$notes uv"; }
  fi

  # --- навык из закреплённого коммита (без символических ссылок в чужом репозитории) ---
  skill_pinned() { # репозиторий коммит навыки(через пробел или *) маркер
    local repo="$1" sha="$2" skill="$3" marker="$4" dir="$work/$4" skill_args
    read -r -a skill_args <<<"$skill"
    if has_skill "$marker"; then ok "$marker"; return; fi
    : >"$log"
    if [ "$node_ok" -ne 1 ] || [ "$git_ok" -ne 1 ]; then fail "$marker" "нужны git и Node 22.20 или новее"; return; fi
    git -c protocol.file.allow=never clone -q --no-recurse-submodules "https://github.com/$repo.git" "$dir" >>"$log" 2>&1 && git -C "$dir" checkout -q "$sha" >>"$log" 2>&1 || { fail "$marker" "не скачалось"; return; }
    # Ссылки CLAUDE.md и GEMINI.md на AGENTS.md в корне (так у greensock/gsap-skills) безвредны и не копируются;
    # папка packages/ (исходники инструментов HyperFrames) не устанавливается. Любая другая ссылка — отказ.
    if [ -n "$(find "$dir" -type l -not -path '*/.git/*' -not -path "$dir/packages/*" -not \( -path "$dir/CLAUDE.md" -o -path "$dir/GEMINI.md" \) 2>/dev/null | head -1)" ] \
      || { [ -L "$dir/CLAUDE.md" ] && [ "$(readlink "$dir/CLAUDE.md")" != "AGENTS.md" ]; } \
      || { [ -L "$dir/GEMINI.md" ] && [ "$(readlink "$dir/GEMINI.md")" != "AGENTS.md" ]; }; then
      fail "$marker" "в репозитории символические ссылки"; return
    fi
    limited 300 npx --yes "$SKILLS_CLI" add "$dir" --skill "${skill_args[@]}" -g -a claude-code -y --copy >>"$log" 2>&1
    if has_skill "$marker"; then done_ "$marker"; else fail "$marker" "npx skills add"; fi
  }

  skill_pinned vercel-labs/skills 7a5e920bead4b1039a6d6df5d7e1163b7b09423a find-skills find-skills
  skill_pinned pbakaus/impeccable 9fadc41729c38fd47d7ae622b501558653f9d2e9 impeccable impeccable
  skill_pinned emilkowalski/skills f1090bec277140d02ed202440185ad9d02ac1490 emil-design-eng emil-design-eng
  skill_pinned blader/humanizer 0ef9fe5bc3572734fd3ae6c448fe00a30cd5dcf0 humanizer humanizer
  # 1.1: анимации, видео, документы
  skill_pinned emilkowalski/skills f1090bec277140d02ed202440185ad9d02ac1490 "apple-design animate animation-vocabulary find-animation-opportunities improve-animations" apple-design
  skill_pinned greensock/gsap-skills "$GSAP_SHA" "gsap-core gsap-frameworks gsap-performance gsap-plugins gsap-react gsap-scrolltrigger gsap-timeline gsap-utils" gsap-core
  skill_pinned heygen-com/hyperframes "$HYPERFRAMES_SHA" "hyperframes hyperframes-cli hyperframes-registry media-use" hyperframes
  skill_pinned remotion-dev/skills "$REMOTION_SHA" '*' remotion-best-practices
  skill_pinned anthropics/skills "$ANTHROPIC_SKILLS_SHA" "pdf docx pptx xlsx" pdf

  # --- плагины Claude Code ---
  if [ -z "$claude_bin" ]; then
    fail superpowers "команда claude не найдена"; fail claude-mem "команда claude не найдена"; fail ecc "команда claude не найдена"
  else
    # Официальный маркетплейс Anthropic: Superpowers, frontend-design, security-guidance
    local official
    for official in superpowers frontend-design security-guidance; do
      if plugin_ready "$claude_bin" "$official@claude-plugins-official"; then ok "$official"
      else
        : >"$log"
        limited 90 "$claude_bin" plugin marketplace add anthropics/claude-plugins-official >>"$log" 2>&1
        limited 180 "$claude_bin" plugin install "$official@claude-plugins-official" >>"$log" 2>&1
        plugin_ready "$claude_bin" "$official@claude-plugins-official" && done_ "$official" || fail "$official" "claude plugin install"
      fi
    done

    # claude-mem: память между сессиями, маркетплейс автора на закреплённом теге
    if plugin_ready "$claude_bin" claude-mem@thedotmack; then ok claude-mem
    elif ! tag_matches thedotmack/claude-mem v15.0.1 "$CLAUDE_MEM_SHA"; then fail claude-mem "тег v15.0.1 не совпал с закреплённым коммитом"
    else
      : >"$log"
      limited 120 "$claude_bin" plugin marketplace add "$CLAUDE_MEM_MARKETPLACE" >>"$log" 2>&1
      limited 240 "$claude_bin" plugin install claude-mem@thedotmack --scope user >>"$log" 2>&1
      plugin_ready "$claude_bin" claude-mem@thedotmack && done_ claude-mem || fail claude-mem "claude plugin install"
    fi

    # ECC: официальный установщик (режим хуков standard), запасной путь — маркетплейс на закреплённом теге
    if plugin_ready "$claude_bin" ecc@ecc; then ok ecc
    elif [ "$node_ok" -ne 1 ] || [ "$git_ok" -ne 1 ]; then fail ecc "нужны git и Node 22.20 или новее"
    elif ! tag_matches affaan-m/ECC v2.2.3 "$ECC_SHA"; then fail ecc "тег v2.2.3 не совпал с закреплённым коммитом"
    else
      : >"$log"
      limited 420 npx --yes "$ECC_NPM" install --guided --harness claude --claude-scope user --claude-hooks standard --yes >>"$log" 2>&1
      if ! plugin_ready "$claude_bin" ecc@ecc; then
        limited 120 "$claude_bin" plugin marketplace add "$ECC_MARKETPLACE" >>"$log" 2>&1
        limited 240 "$claude_bin" plugin install ecc@ecc --scope user >>"$log" 2>&1
      fi
      plugin_ready "$claude_bin" ecc@ecc && done_ ecc || fail ecc "npx ecc-universal install"
    fi
  fi

  # --- Playwright MCP: свой браузер для Claude ---
  if has_mcp playwright; then ok playwright
  elif [ -z "$claude_bin" ]; then fail playwright "команда claude не найдена"
  elif [ "$node_ok" -ne 1 ]; then fail playwright "нужен Node 22.20 или новее"
  else
    : >"$log"
    mkdir -p "$MCP_PREFIX" && limited 300 npm install --prefix "$MCP_PREFIX" --ignore-scripts --no-audit --no-fund "$PLAYWRIGHT_MCP" >>"$log" 2>&1
    local pw_bin="$MCP_PREFIX/node_modules/.bin/playwright-mcp"
    is_windows && [ -f "$pw_bin.cmd" ] && pw_bin="$pw_bin.cmd"
    [ -e "$pw_bin" ] && limited 60 "$claude_bin" mcp add --scope user playwright -- "$pw_bin" >>"$log" 2>&1
    has_mcp playwright && done_ playwright || fail playwright "claude mcp add playwright"
  fi

  # --- Context7 MCP: свежая документация библиотек (ставится в свою папку, как Playwright) ---
  if has_mcp context7; then ok context7
  elif [ -z "$claude_bin" ]; then fail context7 "команда claude не найдена"
  elif [ "$node_ok" -ne 1 ]; then fail context7 "нужен Node 22.20 или новее"
  else
    : >"$log"
    mkdir -p "$MCP_PREFIX" && limited 300 npm install --prefix "$MCP_PREFIX" --ignore-scripts --no-audit --no-fund "$CONTEXT7_MCP" >>"$log" 2>&1
    local c7_bin="$MCP_PREFIX/node_modules/.bin/context7-mcp"
    is_windows && [ -f "$c7_bin.cmd" ] && c7_bin="$c7_bin.cmd"
    [ -e "$c7_bin" ] && limited 60 "$claude_bin" mcp add --scope user context7 -- "$c7_bin" >>"$log" 2>&1
    has_mcp context7 && done_ context7 || fail context7 "claude mcp add context7"
  fi

  # --- graphify: карта знаний по папке (CLI через uv, навык регистрирует сам graphify) ---
  if has_skill graphify; then ok graphify
  elif ! command -v uv >/dev/null 2>&1; then fail graphify "нет uv"
  else
    : >"$log"
    limited 600 uv tool install --force "$GRAPHIFY_PKG" >>"$log" 2>&1
    command -v graphify >/dev/null 2>&1 && limited 120 graphify install >>"$log" 2>&1
    has_skill graphify && done_ graphify || fail graphify "uv tool install graphifyy, graphify install"
  fi

  # --- Agent Reach: zip релиза автора + проверка SHA-256 ---
  ar_ready() { has_skill agent-reach && agent-reach version 2>/dev/null | grep -q '"ok": true'; }
  if ar_ready; then ok agent-reach
  elif ! command -v uv >/dev/null 2>&1; then fail agent-reach "нет uv"
  else
    : >"$log"
    curl --proto =https --tlsv1.2 -fsSL --max-time 120 -o "$work/ar.zip" "$AR_URL" >>"$log" 2>&1
    if [ "$(sha256_of "$work/ar.zip")" = "$AR_SHA256" ]; then
      limited 600 uv tool install --force "$work/ar.zip" >>"$log" 2>&1 && limited 300 agent-reach setup </dev/null >>"$log" 2>&1
    else
      echo "контрольная сумма Agent Reach не совпала, не ставлю" >>"$log"
    fi
    ar_ready && done_ agent-reach || fail agent-reach "uv tool install из релиза v1.6.1"
  fi

  local final=ok
  [ "$fails" -ne 0 ] && final=partial
  write_state "$final" "$tries" "$(echo $missing)" "$(echo $notes)"
  echo "ошибок: $fails"
}

case "${1:-}" in
  --notice) notice_mode; exit 0 ;;
  --auto)   auto_mode; exit 0 ;;
  --run)    run_mode ;;
  --retry)  rm -f "$STATE"; run_mode ;; # повтор после исправления (Node, Git): сбрасывает счётчик попыток
  *)        echo "использование: kit-install.sh --notice | --auto | --run | --retry"; exit 0 ;;
esac
