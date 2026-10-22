# zapret — инструкция по использованию

Обход блокировки YouTube на этой машине. Единая точка входа — скрипт
`service.sh` в корне репозитория.

```bash
cd /home/foxcoder/prog/zapret
./service.sh            # покажет список всех команд
```

## Текущая схема

- **Репозиторий**: `/home/foxcoder/prog/zapret` — git, единственный источник
  файлов (upstream `bol-van/zapret` + локальные коммиты).
- **`/opt/zapret`** — симлинк на репозиторий (systemd-юнит требует этот путь,
  но реальные файлы живут в git).
- **Сервис**: `zapret.service` (enabled, стартует с системы). Он запускает
  `nfqws` и добавляет правила nftables (перехват TCP 80/443 и UDP 443 →
  очередь 200).
- **Стратегия**: только YouTube. QUIC (udp/443) — fake-пакет
  `quic_initial_www_google_com.bin`, TLS (tcp/443) — fake ClientHello +
  мультидизордерный сплит. Обрабатываются только домены из хостлиста.

## Ежедневное использование

Обычно делать нечего — сервис работает в фоне. Просто открывайте YouTube.

| Команда | Что делает |
|---|---|
| `./service.sh status` | состояние сервиса, nfqws и правил nft |
| `./service.sh check` | быстрая проверка доступности YouTube |
| `./service.sh log` | последние 50 строк журнала |
| `sudo ./service.sh start` / `stop` / `restart` | управление обходом |
| `sudo ./service.sh validate` | проверка опций nfqws (как её делает установщик) |
| `sudo ./service.sh test` | blockcheck — подбор стратегии, если обход сломался |
| `sudo ./service.sh update` | git pull upstream + пересборка + переустановка |
| `sudo ./service.sh install` | (пере)установка сервиса |
| `sudo ./service.sh uninstall` | полное удаление из системы |

Обычные systemd-команды тоже работают:
`systemctl status zapret`, `sudo systemctl restart zapret`.

## Если YouTube снова перестал работать

```bash
./service.sh status      # жив ли сервис и nfqws
./service.sh log         # ошибки в журнале
sudo ./service.sh test    # blockcheck подберёт рабочую стратегию под провайдера
```

`blockcheck` в конце печатает рабочие опции — перенесите их в `NFQWS_OPT`
в файле `config` и выполните `sudo ./service.sh restart`.

## Правка конфигурации

Все пути — внутри репозитория `/home/foxcoder/prog/zapret`.

- **Список сайтов для обхода** — `ipset/zapret-hosts-user.txt`
  (сейчас: youtube.com, youtu.be, googlevideo.com, ytimg.com, ggpht.com,
  youtube-nocookie.com, youtubei.googleapis.com, yt3.ggpht.com,
  yt3.googleusercontent.com). Добавили домен — допишите строкой и:
  ```bash
  sudo ./service.sh restart
  ```
- **Стратегия обхода** — переменная `NFQWS_OPT` в файле `config`
  (после правки тоже `restart`).
- Проверить опции без перезапуска: `sudo ./service.sh validate`.

## Обновление zapret

```bash
cd /home/foxcoder/prog/zapret
sudo ./service.sh update      # fetch upstream, merge, сборка, переустановка
```

Если merge конфликтует по `config` — разрешите вручную, затем
`sudo ./service.sh install`.

## Git-workflow

- Рабочая ветка — `main`, для изменений создаётся `feature/...`,
  коммит после каждого логического шага, затем merge в `main`.
- `origin` переименован в **`upstream`** — это чужой репозиторий
  (bol-van/zapret), пушить туда нельзя и не нужно.
- Свои файлы под git: `config`, `ipset/zapret-hosts-user.txt`, `service.sh`.
  Артефакты сборки `binaries/` — в `.gitignore`.
- Когда появится свой remote (GitHub/Gitea) — добавить его как `origin`
  и пушить после каждого коммита.
- Обновления от автора приходят через `upstream` (`service.sh update`).

## Важные нюансы этой установки

1. **`/home/foxcoder` имеет права `701`** — это обязательно: nfqws при
   запуске от root понижает привилегии и потом открывает файлы хостлистов,
   поэтому «чужим» uid нужно право прохода (`o+x`) по пути до репозитория.
   Не меняйте домашний каталог на `700` — обход сломается.
2. **Пакет для сборки в Arch** называется `libnetfilter_queue` (с
   подчёркиванием), а не `libnetfilter-queue`.
3. Сборка после правок: `make systemd` (не требует root).
4. Установочные скрипты задают вопросы — все ответы по умолчанию
   корректны, достаточно Enter.

## Полное удаление

```bash
sudo ./service.sh uninstall   # сервис, правила, симлинк /opt/zapret
rm -rf /home/foxcoder/prog/zapret   # сам git-репозиторий
```
