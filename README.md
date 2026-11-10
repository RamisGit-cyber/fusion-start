# Fusion Старт

Плагин Claude Code от Fusion AI. Ставит базовый набор, с которым мы настраиваем Claude своим клиентам: память между сессиями, работа по плану, готовые помощники, карта знаний, чтение интернета, навыки дизайна и свой браузер.

> **Важно до установки.** В набор входит ECC в режиме хуков Standard: его помощники могут отправлять выжимку разговора во внешнюю модель. claude-mem хранит историю сессий у вас на компьютере (включая то, что вы написали в чате). Не пишите в чат пароли и ключи.

## Установка

Нужно: Claude Desktop (claude.ai/download) с подпиской Pro или Max, Git и Node.js LTS (nodejs.org). Откройте вкладку **Code**, выберите любую папку и вставьте в чат:

```
Установи плагин Fusion Старт: запусти claude plugin marketplace add RamisGit-cyber/fusion-start, потом claude plugin install fusion-start@fusion-start и скажи, когда закончишь.
```

Если Claude пишет «Operation not permitted», вставьте команды в поле ввода по очереди, каждую отдельным сообщением:

```
/plugin marketplace add RamisGit-cyber/fusion-start
/plugin install fusion-start@fusion-start
```

Затем полностью закройте и откройте Claude Desktop. При первом запуске плагин сам поставит набор в фоне (5–15 минут) и скажет, когда закончит. После этого перезапустите приложение ещё раз.

Проверка: напишите в Code «покажи, какие плагины и навыки у меня стоят».

## Что ставится

| Что | Источник | Лицензия |
|---|---|---|
| claude-mem | thedotmack/claude-mem, тег v15.0.1 | Apache-2.0 |
| Superpowers | obra/superpowers через claude-plugins-official | MIT |
| ECC | affaan-m/ECC, ecc-universal 2.2.3, хуки Standard | MIT |
| graphify | graphifyy 0.9.105 (Graphify-Labs/graphify) | Apache-2.0 |
| Agent Reach | Panniantong/Agent-Reach v1.6.1, проверка SHA-256 | MIT |
| find-skills | vercel-labs/skills | MIT |
| impeccable | pbakaus/impeccable | Apache-2.0 |
| emil-design-eng | emilkowalski/skills | MIT |
| humanizer | blader/humanizer | MIT |
| Playwright MCP | @playwright/mcp 0.0.84 | Apache-2.0 |
| uv | astral.sh, 0.13.4 | MIT / Apache-2.0 |

Чужой код в этот репозиторий не копируется: всё скачивается у авторов на закреплённых версиях и коммитах.

## Как это работает и приватность

Плагин — это один скрипт `hooks/kit-install.sh` и один навык с подсказками. Приложение запускает скрипт при старте сессии как хук (хуки идут вне песочницы, поэтому могут писать в `~/.claude`). Скрипт ставит только недостающее, уже поставленное не трогает, делает не больше трёх попыток. Состояние и журнал — в `~/.fusion-start/`.

Сам плагин ничего не отправляет ни нам, ни третьим лицам. Установка скачивает файлы с GitHub, npm, PyPI и astral.sh. ECC в режиме Standard может отправлять выжимку разговора во внешнюю модель — это поведение самого ECC, его можно выключить.

Выключить набор: создайте пустой файл `~/.fusion-start/off`.

## Лицензия

MIT, см. `LICENSE`.
