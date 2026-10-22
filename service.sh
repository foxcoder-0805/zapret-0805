#!/usr/bin/env bash
# Единая точка входа для управления zapret.
# Заменяет запоминание кучи команд: service.sh <команда>
set -euo pipefail

ZAPRET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ZAPRET_DIR"

c_red='' c_grn='' c_yel='' c_off=''
[ -t 1 ] && { c_red=$'\e[31m'; c_grn=$'\e[32m'; c_yel=$'\e[33m'; c_off=$'\e[0m'; }

ok()   { echo "${c_grn}✓${c_off} $*"; }
warn() { echo "${c_yel}!${c_off} $*"; }
die()  { echo "${c_red}✗${c_off} $*" >&2; exit 1; }

need_root() {
	[ "$(id -u)" -eq 0 ] || die "команда «$1» требует root: sudo ./service.sh $1"
}

usage() {
	cat <<EOF
Управление zapret : $ZAPRET_DIR

  $0 install    установить/переустановить сервис (первый запуск, после update)
  $0 start      запустить обход блокировок
  $0 stop       остановить обход
  $0 restart    перезапуск (после правки config или хостлистов)
  $0 status     состояние сервиса и nfqws
  $0 log        последние 50 строк журнала
  $0 validate   проверка опций nfqws (как её делает установщик, нужен root)
  $0 check      проверить, работает ли обход (доступность YouTube)
  $0 test       прогнать blockcheck.sh (подбор стратегии при поломке)
  $0 update     обновить zapret из upstream + пересобрить и переустановить
  $0 uninstall  полностью удалить zapret из системы
  $0 this       показать этот список
EOF
}

cmd_install() {
	need_root install
	command -v make >/dev/null || die "нет make (нужен пакет make/gcc)"
	echo \* сборка бинарников
	make systemd
	echo "* запуск установщика (все вопросы — Enter)"
	./install_easy.sh
	ok "установка завершена"
}

cmd_start()   { need_root start;   systemctl start zapret;   ok "zapret запущен"; }
cmd_stop()    { need_root stop;    systemctl stop zapret;    ok "zapret остановлен"; }
cmd_restart() { need_root restart; systemctl restart zapret; ok "zapret перезапущен"; }

cmd_status() {
	echo \* сервис
	systemctl status zapret --no-pager -l || true
	echo
	echo \* nfqws
	if pgrep -a nfqws >/dev/null; then
		pgrep -a nfqws
	else
		warn "nfqws не работает"
	fi
	echo
	echo \* nftables
	nft list ruleset 2>/dev/null | grep -c zapret >/dev/null \
		&& ok "правила zapret присутствуют в nft" \
		|| warn "правил zapret в nft нет"
}

cmd_log() { journalctl -u zapret -n 50 --no-pager; }

cmd_validate() {
	# повторяет проверку установщика : nfqws --dry-run от root (как под sudo).
	# именно так ловится ошибка droproot : root-процесс не может прочитать
	# хостлисты, если путь к ним закрыт для «чужих» uid (например 700 в ~/)
	need_root validate
	echo "* валидация NFQWS_OPT как её делает install_easy.sh"
	# shellcheck disable=SC1091
	. "$ZAPRET_DIR/config"
	local opt="$NFQWS_OPT" qn=${QNUM:-200}
	if "$ZAPRET_DIR/nfq/nfqws" --dry-run --qnum=$qn $opt; then
		ok "опции nfqws валидны"
	else
		die "nfqws отверг опции — если сказано «cannot access hostlist file», закрыт доступ к каталогу: sudo chmod o+x ~"
	fi
}

cmd_check() {
	echo \* проверка доступности
	local rc=0 code
	# youtube main page via HTTP code
	code=000
	code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 https://www.youtube.com/ 2>/dev/null) || true
	code=${code:-000}
	if [ "$code" = "200" ]; then
		ok "youtube.com отвечает (HTTP $code)"
	else
		warn "youtube.com: HTTP $code (обход, вероятно, не работает)"
		rc=1
	fi
	# QUIC probe : udp/443 to googlevideo should be reachable
	if timeout 3 bash -c 'echo -n >/dev/udp/142.250.0.1/443' 2>/dev/null; then
		ok "udp/443 (QUIC) исходящий проходит"
	else
		warn "udp/443 недоступен"
	fi
	[ $rc -eq 0 ] || { echo; warn "если YouTube не грузится: sudo ./service.sh test"; }
	return $rc
}

cmd_test() {
	need_root test
	echo \* запуск blockcheck — подбор стратегии под вашего провайдера
	echo "  (займёт несколько минут, в конце будет готовый конфиг)"
	./blockcheck.sh
}

cmd_update() {
	echo \* обновление из upstream
	git fetch upstream || die "не удалось получить upstream"
	local base
	base=$(git merge-base HEAD upstream/master 2>/dev/null || git merge-base HEAD upstream/main)
	git log --oneline HEAD.."$base"..upstream/master 2>/dev/null | head || true
	if git diff --quiet HEAD upstream/master -- . ':(exclude)config' 2>/dev/null; then
		ok "upstream не изменился"
		return
	fi
	# свои правки конфига коммитим заранее, чтобы merge был чистым
	[ -n "$(git status --porcelain config ipset/zapret-hosts-user.txt)" ] && \
		git add config ipset/zapret-hosts-user.txt && \
		git commit -q -m "chore(config): local changes before update"
	git merge upstream/master || {
		warn "конфликт в config — разрешите вручную: $ZAPRET_DIR/config"
		die "после разрешения повторите: sudo ./service.sh install"
	}
	echo \* пересборка и переустановка
	cmd_install
	cmd_restart
	ok "zapret обновлён"
}

cmd_uninstall() {
	need_root uninstall
	./uninstall_easy.sh || true
	[ -L /opt/zapret ] && rm -f /opt/zapret && ok "симлинк /opt/zapret удалён"
	ok "zapret из системы удалён (git-репозиторий сохранён: $ZAPRET_DIR)"
	echo "  полное удаление репозитория: rm -rf $ZAPRET_DIR"
}

cmd=${1:-this}
case "$cmd" in
	install)   cmd_install ;;
	start)     cmd_start ;;
	stop)      cmd_stop ;;
	restart)   cmd_restart ;;
	status)    cmd_status ;;
	log)       cmd_log ;;
	validate)  cmd_validate ;;
	check)     cmd_check ;;
	test)      cmd_test ;;
	update)    cmd_update ;;
	uninstall) cmd_uninstall ;;
	this|-h|--help|help) usage ;;
	*) usage; die "неизвестная команда: $cmd" ;;
esac
