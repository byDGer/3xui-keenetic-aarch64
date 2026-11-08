#!/opt/bin/bash
# =============================================================================
#  x-ui.sh — управляющий скрипт панели 3x-ui для роутеров Keenetic (Entware)
# -----------------------------------------------------------------------------
#  Что делает:
#    • устанавливает и обновляет панель 3x-ui (всегда последняя версия с GitHub MHSanaei/3x-ui);
#    • включает HTTPS (самоподписанный сертификат) и умеет получать сертификат Let's Encrypt для вашего домена;
#    • запускает/останавливает панель, включает автозапуск, меняет логин, пароль, порт;
#    • делает резервные копии базы данных (вручную, перед обновлением панели и по расписанию), выгружает её в json, обновляет geo-файлы;
#    • показывает в шапке меню версии скрипта, панели и Xray с цветными точками (зелёная — самая свежая версия, жёлтая — есть обновление,
#      красная — проверить не удалось), адрес панели, срок действия SSL-сертификата и предупреждение о неверном времени;
#    • обновляет ядро Xray отдельно от панели (последняя или выбранная версия, откат на прежнюю);
#    • Let's Encrypt для вашего домена: проверка по HTTP (порт 80) или через DNS-API провайдера, тестовый режим staging;
#    • диагностика установки (doctor) и мастер доступа из интернета (remote_access);
#    • команды для мониторинга и cron: status --json, update --check (коды возврата), backup_auto;
#    • обновляет сам себя из репозитория SCRIPT_REPO (см. CURRENT_VERSION_SCRIPT) с проверкой контрольной суммы x-ui.sh.sha256.
#
#  Как запускать (на роутере, в Entware, от root):
#    bash x-ui.sh                  — при первом запуске предложит выбор: автоматическая установка или самостоятельная настройка;
#                                    после установки откроет меню управления (то же самое делает команда x-ui)
#    x-ui <команда>                — выполнить команду без меню, например:
#                                    start | stop | restart | status | enable | disable | view_panel | ssl | ssl_domain | ssl_remove | update | update_xray |
#                                    update_xray_custom | rollback_xray | backup_auto | backup_cron | doctor | remote_access
#                                    x-ui status --json (состояние в JSON), x-ui update --check (коды: 0 — всё последнее, 10 — есть обновления, 2 — не удалось проверить)
#    bash x-ui.sh auto_install     — автоматическая установка без вопросов
#
#  Где что лежит:
#    /opt/etc/x-ui/                — панель, база (db), сертификаты (cert), резервные копии (backup), кэш (cache), настройки (config)
#    /opt/etc/init.d/S99x-ui       — ссылка автозапуска (появляется после enable)
#    /opt/bin/x-ui                 — команда для вызова меню
#    /opt/var/log/script_x-ui.log  — журнал этого скрипта
#
#  Как устроено меню: пункты описаны текстом «ключ::Русский текст». Ключ — это имя функции, которая
#  вызывается при выборе, текст видит пользователь. Строка [br] рисует разделительную линию.
#  Поэтому, чтобы добавить пункт, достаточно написать функцию и добавить строку «имя_функции::Текст» в нужное меню.
# =============================================================================

# START VARIABLES  ------------------------------------------------------------
# Цвета и стили текста в консоли (коды ANSI).
# Раздел «Переменные»: цвета, значки, версии, пути к файлам и настройки. Здесь же — настройки автоматического режима.
color_bg_white='\033[47m'

style_new_line='\033c'
style_blink='\033[5m'
style_reverse='\033[7m'
style_plain='\033[0m'

color_black='\033[0;30m'
color_red='\033[0;31m'
color_green='\033[0;32m'
color_yellow='\033[0;33m'
color_blue='\033[0;34m'
color_magenta='\033[0;35m'
color_cyan='\033[0;36m'
color_white='\033[0;37m'

color_bgreen='\033[1;32m'

# Значки перед сообщениями: успех, ошибка, работа, информация, предупреждение.
declare -A ICO_MAP=( [GOOD]="[ ✔ ]" [BAD]="[ ✘ ]" [WORK]="[ ⚙ ]" [INF]="[INF]" [ERR]="[ERR]" [WAR]="[⚠️]" )

# Версия этого скрипта. При выпуске обновления её нужно увеличить: по ней скрипт понимает, что на GitHub есть новая версия.
CURRENT_VERSION_SCRIPT="1.1.0"
# Репозиторий, из которого скрипт обновляет сам себя (ветка main).
SCRIPT_REPO="byDGer/3xui-keenetic-aarch64"
SCRIPT_RAW="https://raw.githubusercontent.com/$SCRIPT_REPO"
# Ветка или тег для скачивания скрипта: пусто — брать тег по номеру версии, main — брать последнюю версию.
SCRIPT_REF=""
# Версии панели и скрипта: установленные (CURRENT_*) и самые новые на GitHub (LAST_*).
CURRENT_VERSION_PANEL=""
LAST_VERSION_PANEL=""
LAST_VERSION_SCRIPT=""
CURRENT_VERSION_ALL=""


# Имя исполняемого файла панели (xui) и короткое имя команды (x-ui).
NAME_APP=xui
# Приоритет автозапуска: ссылка будет называться S99x-ui (чем больше число, тем позже запускается).
PRIORITY="S99"
SHELL_SHORT_NAME="x-ui"
SHELL_FULL_NAME="$SHELL_SHORT_NAME.sh"

# Пути: все файлы лежат в /opt (Entware).
DIR_NOTREAL_CUR=$(dirname "$0")
DIR_ENTWARE='/opt'
DIR_TMP=$DIR_ENTWARE'/tmp'
DIR_INSTALL_LNK=$DIR_ENTWARE'/bin/'$SHELL_SHORT_NAME
DIR_MAIN=$DIR_ENTWARE'/etc'
DIR_AUTO_START=$DIR_MAIN'/init.d'
DIR_PROJECT=$DIR_MAIN'/'$SHELL_SHORT_NAME
DIR_DB="$DIR_PROJECT/db"
DIR_LOGFILE="$DIR_ENTWARE/var/log/script_$SHELL_SHORT_NAME.log"
DIR_DB_IN_JSON="$DIR_PROJECT/db_in_json"
DIR_CACHE="$DIR_PROJECT/cache"
DIR_PROJECT_SHELL_SCRIPTS="$DIR_PROJECT/$SHELL_FULL_NAME"
DIR_CERT="$DIR_PROJECT/cert"
DIR_ACME="$DIR_ENTWARE/etc/acme.sh"
DIR_CONFIG="$DIR_PROJECT/config"

# Файл базы данных панели.
DB="$DIR_DB/$SHELL_SHORT_NAME.db"

NAME_NOTREAL_SHELL=$(basename "$0")
# Редактор для просмотра журнала и файла настроек.
DEFAULT_EDITOR="nano"
ARCHITECTURE=""
COMMANDS_CALL=""

# Настройки скрипта (хранятся в /opt/etc/x-ui/config/settings и подхватываются при запуске):
# DEBUG_SCRIPT — показывать цепочку вызовов функций, LOG_SCRIPT — вести журнал,
# CHECK_UPDATES — проверять на GitHub наличие новых версий для цветных точек в шапке меню (false — не обращаться к сети при открытии меню),
# BACKUP_KEEP — сколько последних автоматических резервных копий базы хранить (остальные удаляются).
DEBUG_SCRIPT=false
LOG_SCRIPT=true
CHECK_UPDATES=true
BACKUP_KEEP=10
# Переменные окружения, которые читает сама панель: где её ядро, база данных и журнал.
XUI_BIN_FOLDER="$DIR_PROJECT/bin"
XUI_DB_FOLDER="$DIR_DB"
XUI_LOG_FOLDER="$DIR_ENTWARE/var/log/$SHELL_SHORT_NAME"
XUI_LOG_LEVEL="error" # possible values: debug, info, notice, warning, error
XUI_DEBUG="false"
# Ответы пользователя на вопросы: map_confirm[имя] = введённое значение.
declare -A map_confirm
# Автоматический режим: 1 — вопросы не задаются, берутся значения по умолчанию.
# AUTO_USER / AUTO_PASS / AUTO_PATH — случайные логин, пароль и путь панели; подставляются как значения по умолчанию.
AUTO_MODE=0
AUTO_USER=""
AUTO_PASS=""
AUTO_PATH=""
# END VARIABLES ------------------------------------------------------------
# START PREPARATION --------------------------------------------------------
# Если нет ни базы, ни скрипта в рабочем каталоге — это чистая система, кэш не нужен.
# Иначе читаем сохранённые настройки скрипта (или создаём файл настроек со значениями по умолчанию).
# Раздел «Подготовка»: загрузка настроек скрипта, вывод в журнал, определение настоящего пути скрипта, проверка системы.
if [[ ! -f $DB && ! -f $DIR_PROJECT_SHELL_SCRIPTS ]]; then
    no_cache_needed=1
else
	if [[ -f "$DIR_CONFIG/settings" ]]; then
		source "$DIR_CONFIG/settings"
	else
		if [[ ! -d "$DIR_CONFIG" ]]; then
			mkdir -p "$DIR_CONFIG"
		fi
		echo -e "DEFAULT_EDITOR=\"$DEFAULT_EDITOR\"" >> "$DIR_CONFIG/settings"
		echo -e "DEBUG_SCRIPT=\"$DEBUG_SCRIPT\"" >> "$DIR_CONFIG/settings"
		echo -e "LOG_SCRIPT=\"$LOG_SCRIPT\"" >> "$DIR_CONFIG/settings"
		echo -e "CHECK_UPDATES=\"$CHECK_UPDATES\"" >> "$DIR_CONFIG/settings"
		echo -e "BACKUP_KEEP=\"$BACKUP_KEEP\"" >> "$DIR_CONFIG/settings"
		echo -e "XUI_BIN_FOLDER=\"$XUI_BIN_FOLDER\"" >> "$DIR_CONFIG/settings"
		echo -e "XUI_DB_FOLDER=\"$XUI_DB_FOLDER\"" >> "$DIR_CONFIG/settings"
		echo -e "XUI_LOG_FOLDER=\"$XUI_LOG_FOLDER\"" >> "$DIR_CONFIG/settings"
		echo -e "XUI_LOG_LEVEL=\"$XUI_LOG_LEVEL\"" >> "$DIR_CONFIG/settings"
		echo -e "XUI_DEBUG=\"$XUI_DEBUG\"" >> "$DIR_CONFIG/settings"
	fi
fi

# Переменные окружения для панели (часовые пояса, пути к файлам).
export ZONEINFO=/opt/share/zoneinfo
export XUI_BIN_FOLDER="$XUI_BIN_FOLDER"
export XUI_DB_FOLDER="$XUI_DB_FOLDER"
export XUI_LOG_FOLDER="$XUI_LOG_FOLDER"
export XUI_LOG_LEVEL="$XUI_LOG_LEVEL"
export XUI_DEBUG="$XUI_DEBUG"

# Убирает из текста цветовые коды (ANSI), чтобы в журнал попадал чистый текст.
strip_ansi() {
    sed -E $'s/\x1B\[[0-9;?]*[ -/]*[@-~]//g; s/\033\[[0-9;?]*[ -/]*[@-~]//g; s/\e\[[0-9;?]*[ -/]*[@-~]//g; s/\x1B//g; s/\033//g; s/\e//g'
}

# Выдаёт случайную строку из латинских букв и цифр. Параметр 1 — длина (по умолчанию 12).
# Только буквы и цифры: такие значения безопасно подставлять в команды и адреса.
random_string() {
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "${1:-12}"
}

# IP-адрес роутера в локальной сети (интерфейс br0). Понимает оба формата вывода ifconfig
# («inet addr:192.168.1.1» и «inet 192.168.1.1»), а если ifconfig не помог — берёт адрес командой ip.
lan_ip() {
    local addr
    addr=$(ifconfig br0 2>/dev/null | sed -n -e 's/.*inet addr:\([0-9.]*\).*/\1/p' -e 's/^[[:space:]]*inet \([0-9.]*\).*/\1/p' | head -n1)
    if [[ -z "$addr" ]]; then
        addr=$(ip -4 -o addr show br0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)
    fi
    echo "$addr"
}

# Главная функция вывода сообщений.
# Печатает текст на экран и дублирует его в файл журнала вместе с датой и цепочкой вызовов функций.
# Параметр 1 — сообщение, параметр 2 — слово nolog (писать только в журнал, на экран не выводить).
# При DEBUG_SCRIPT=true дополнительно показывает цепочку вызовов.
# Работает без запуска внешних программ (date, sed): дата берётся встроенной printf, цветовые коды вырезаются подстановками bash.
# Раньше каждое сообщение запускало 4 процесса (date и 3 sed), а на одно открытие меню приходилось около 11 сообщений.
logmsg() {
    local msg="$1"
    local onlylog="$2"
    local stack="" plain_stack="" i now clean
    # Цепочка вызовов нужна только для журнала и отладки: иначе не тратим время на её сборку
    if [[ "$LOG_SCRIPT" == true || "$DEBUG_SCRIPT" == true ]]; then
        for ((i=${#FUNCNAME[@]}-1; i>0; i--)); do
            stack+="${FUNCNAME[$i]}"
            plain_stack+="${FUNCNAME[$i]}"
            if [[ $i -ne 1 ]]; then
                stack+=" ${color_cyan}->${style_plain} "
                plain_stack+=" -> "
            fi
        done
    fi
    if [[ "$LOG_SCRIPT" == true ]]; then
        printf -v now '%(%Y-%m-%d %H:%M:%S)T' -1
        # Раскрываем \033, \n и т. п. (как echo -e) и вырезаем цветовые последовательности ESC[...m и прочие управляющие коды
        printf -v clean '%b' "$msg"
        local ansi_re=$'\e''\[[0-9;?]*[ -/]*[@-~]'
        while [[ "$clean" =~ $ansi_re ]]; do
            clean="${clean//"${BASH_REMATCH[0]}"/}"
        done
        clean="${clean//$'\e'/}"
        # Как и раньше, конечные переводы строки в журнал не попадают
        while [[ "$clean" == *$'\n' ]]; do
            clean="${clean%$'\n'}"
        done
        printf '[%s] [TRACE] %s\n[%s] [MESSAGE]%s\n' "$now" "$plain_stack" "$now" "$clean" >> "$DIR_LOGFILE"
        if [[ "$onlylog" != "nolog" ]]; then
            echo -e "$msg"
        fi
    else
        echo -e "$msg"
    fi
    if [ "$DEBUG_SCRIPT" = true ]; then
        DEBUG_TXT="$color_bgreen$stack$style_plain"
        echo -e "${style_blink}[DEBUG]${style_plain} ${style_reverse}${DEBUG_TXT}${style_plain}"
    fi
}

# Определяет настоящий каталог скрипта, даже если он запущен через символическую ссылку (команда x-ui — это ссылка).
real_dir_shell(){
	SOURCE="${BASH_SOURCE[0]}"
	while [ -h "$SOURCE" ]; do
	DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
	SOURCE="$(readlink "$SOURCE")"
	[[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
	done
	SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
	logmsg "$SCRIPT_DIR"
}

# Ротация журнала: если файл вырос больше 512 КБ, он откладывается в script_x-ui.log.1 (прежний .1 заменяется),
# а запись продолжается в новый файл. Так журнал не растёт бесконечно на флешке роутера.
if [[ -f "$DIR_LOGFILE" && $(wc -c < "$DIR_LOGFILE") -gt 524288 ]]; then
    mv -f "$DIR_LOGFILE" "$DIR_LOGFILE.1"
fi
# Настоящее расположение скрипта (с учётом символических ссылок).
DIR_REAL_SHELL=$(real_dir_shell)

# Определяет настоящее имя файла скрипта (с учётом символических ссылок).
real_name(){
	SOURCE="$0"
	while [ -h "$SOURCE" ]; do
	DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
	SOURCE="$(readlink "$SOURCE")"
	[[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
	done
	REAL_PATH="$(cd -P "$(dirname "$SOURCE")" && pwd)/$(basename "$SOURCE")"
	REAL_NAME="$(basename "$REAL_PATH")"
	logmsg "$REAL_NAME"
}

NAME_REAL_SHELL=$(real_name)

# Проверяет, что система — Entware (должна быть программа /opt/bin/opkg). Иначе скрипт завершается.
check_os_release() {
    local release_path=$(command -v opkg)
    if  [[ "$release_path" != "/opt/bin/opkg" ]]; then
        logmsg "${color_red}Неподдерживаемая операционная система!${style_plain}" && exit 1
    fi
    release="entware"
    if [[ -z $1 ]]; then
        logmsg "${ICO_MAP[GOOD]} Дистрибутив ОС: $release"
    fi
}
# Определяет архитектуру процессора и подбирает имя сборки панели (arm64, armv7, 386 и т. д.).
# Параметр 1 — не печатать результат. Для неподдерживаемых процессоров (например, MIPS) скрипт завершается.
check_architecture() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) ARCHITECTURE='amd64' ;;
        i*86 | x86) ARCHITECTURE='386' ;;
        armv8* | arm64 | aarch64) ARCHITECTURE='arm64' ;;
        armv7* | arm) ARCHITECTURE='armv7' ;;
        armv6*) ARCHITECTURE='armv6' ;;
        armv5*) ARCHITECTURE='armv5' ;;
        s390x) ARCHITECTURE='s390x' ;;
        *) logmsg "${color_red}Неподдерживаемая архитектура процессора! ${style_plain}" && exit 1 ;;
    esac
    if [[ -z $1 ]]; then
        logmsg "${ICO_MAP[GOOD]} Архитектура: $ARCHITECTURE"
    fi  
}
# END PREPARATION ------------------------------------------------------------
# START INSTALLATION ------------------------------------------------------------
# Раздел «Установка и обновление»: выбор пунктов меню, установка, обновление, удаление.
# По номеру выбранного пункта возвращает его «ключ» — имя функции, которую нужно вызвать.
# Сначала ищет ключ в menu_key_list (строки вида «номер:ключ»). Если не нашла (например, пункты — это просто имена файлов),
# разбирает текст меню: берёт первое слово в квадратных скобках.
get_menu_word() {
    local menu="$1"
    local number="$2"
    local key
    # у пунктов вида "ключ::Русский текст" имя функции хранится в menu_key_list
    if [[ -n "$menu_key_list" && "$number" =~ ^[0-9]+$ ]]; then
        key=$(echo "$menu_key_list" | grep -m1 "^${number}:" | cut -d: -f2-)
        if [[ -n "$key" ]]; then
            echo "$key" | tr '[:upper:]' '[:lower:]'
            return
        fi
    fi
    echo "$menu" \
      | sed -E 's/\x1B\[[0-9;?]*[ -/]*[@-~]//g' \
      | grep -E "\(${number}\)" \
      | sed -E 's/.*\[([A-Za-z0-9_.]+).*/\1/' \
      | tr '[:upper:]' '[:lower:]'
}

# Устанавливает через opkg всё, что нужно панели и скрипту.
install_base() {
    check_architecture
    logmsg "${ICO_MAP[WORK]} ${color_green}Установка необходимых пакетов...${style_plain}"
    case "${release}" in
    entware)
        # Пакеты: wget и curl — загрузка, tar — распаковка, ca-certificates и *-ssl — HTTPS,
        # sqlite3-cli — работа с базой, jq — разбор json, openssl-util и libopenssl — сертификаты.
        opkg update && opkg install wget curl tar wget-ssl ca-certificates sqlite3-cli jq openssl-util libopenssl
        ;;
    *) logmsg "${color_red}Неподдерживаемый релиз! ${release}" && exit 1
		;;
    esac
}

# Обновляет структуру базы данных после обновления панели (команда panel migrate).
migration(){
    logmsg "${ICO_MAP[WORK]} ${color_yellow}Миграция... ${style_plain}"
    $DIR_PROJECT/$NAME_APP migrate
    logmsg "${ICO_MAP[GOOD]} ${color_yellow}Миграция завершена!${style_plain}"
}

# Первичная настройка после первой установки: порт, путь и адрес панели, затем логин и пароль администратора.
config_after_install() {
    exe_set_panel
    exe_set_admin
}

# Вызывается в самом конце: если в этом запуске показывалось главное меню, ждёт Enter и возвращает в него.
check_show_main_menu(){
    if [[ -n "$show_main_menu" ]]; then
        before_show_main_menu
        return 0
    fi
}

# Показывает меню и читает выбор пользователя. Результат — ключ выбранного пункта в переменной schoice.
# Параметры: 1 — имя меню (переменная с текстом), 2 — готовый выбор (тогда вопрос не задаётся),
# 3 — текст приглашения, 4 — значение по умолчанию, 5 — не использовать кэш меню,
# 6 — функция, превращающая номер в ключ (по умолчанию get_menu_word).
menu_choice(){
local menu=$1
local choice=$2
local txt=${3:-"Введите номер пункта"}
local default_choice=$( [ -n "$4" ] && echo " [по умолчанию: $4]" || echo "" )
local skip_cache=$5
local patern=${6:-"get_menu_word"}
    if [[ -z "$choice" ]]; then
        menu_numeric_choice "$menu" $skip_cache
        echo -e "$menu_numeric_choice_list"
        printf "${style_reverse}%s${style_plain}" "$txt$default_choice [$start_index-$max_num_of_choices]: "; read choice
		if [[ -n "$default_choice" && -z "$choice" ]]; then
			choice=$default_choice
		fi
        clean_menu_numeric_choice_list=$(echo -e "$menu_numeric_choice_list" | strip_ansi)
		schoice="$($patern "$clean_menu_numeric_choice_list" "$choice")"
    else
        schoice="$choice"
    fi
	logmsg $schoice
}

# Путь к файлу ядра Xray внутри панели (например, /opt/etc/x-ui/bin/xray-linux-arm64).
# Копии с суффиксами .bak и .new (резервная копия и временный файл при обновлении) не учитываются.
xray_bin_path() {
    local f
    for f in "$DIR_PROJECT"/bin/xray-linux-*; do
        if [[ -f "$f" && "$f" != *.bak && "$f" != *.new ]]; then
            echo "$f"
            return 0
        fi
    done
    return 1
}

# Последний релиз репозитория на GitHub, например v1.2.3. Параметры: 1 — репозиторий (владелец/имя), 2 — ограничение времени
# каждого запроса в секундах (по умолчанию 8). Сначала берётся из переадресации страницы «releases/latest» (не зависит от лимитов API),
# запасной способ — GitHub API (поле tag_name ищется и в «красивом», и в сжатом JSON). Печатает тег или ничего, если проверить не удалось.
github_latest_tag() {
    local repo="$1" max="${2:-8}" tag
    tag=$(curl -4 -fsSL --max-time "$max" -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest" 2>/dev/null | sed -n 's|.*/releases/tag/\(.*\)|\1|p')
    if [[ -z "$tag" ]]; then
        tag=$(curl -4 -fsSL --max-time "$max" "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
    fi
    echo "$tag"
}

# Версия Xray, которая сейчас стоит в панели (например, 25.8.3).
# Ядро печатает первой строкой «Xray <версия> (...)»: берём второе слово. Если ядра нет или оно не запускается — пусто.
# Запуск ядра — самая дорогая операция при открытии меню, поэтому результат кэшируется в $DIR_CACHE/xray_version
# и перечитывается только тогда, когда файл ядра новее кэша (то есть его заменили: обновление из меню или из панели).
# Время файлов сравнивается встроенной проверкой -nt, без запуска программ.
xray_version() {
    local bin v cache="$DIR_CACHE/xray_version"
    bin=$(xray_bin_path)
    [[ -n "$bin" && -x "$bin" ]] || return 1
    if [[ -f "$cache" && ! "$bin" -nt "$cache" ]]; then
        v=$(<"$cache")
        if [[ -n "$v" ]]; then
            echo "$v"
            return 0
        fi
    fi
    v=$("$bin" -version 2>/dev/null | head -n1 | awk '{print $2}')
    # В некоторых сборках версия запрашивается подкомандой, а не ключом
    if [[ -z "$v" ]]; then
        v=$("$bin" version 2>/dev/null | head -n1 | awk '{print $2}')
    fi
    if [[ -n "$v" ]]; then
        mkdir -p "$DIR_CACHE"
        echo "$v" > "$cache"
    fi
    echo "$v"
}

# Цветная точка статуса по названию цвета: green, yellow или red (зелёная — всё хорошо, жёлтая — внимание, красная — проблема).
status_dot() {
    case "$1" in
        green)  echo -e "${color_green}●${style_plain}" ;;
        yellow) echo -e "${color_yellow}●${style_plain}" ;;
        *)      echo -e "${color_red}●${style_plain}" ;;
    esac
}

# Читает из базы данных панели настройки доступа одним запросом sqlite3 (программа панели для этого не запускается — это быстрее):
# PANEL_PORT, PANEL_PATH, PANEL_LISTEN (адрес прослушивания), PANEL_CERT и PANEL_KEY (пути к сертификату и ключу).
# Возвращает 1, если базы или sqlite3 нет (тогда строки с адресом и сертификатом в шапке не показываются).
panel_settings_read() {
    PANEL_PORT=""
    PANEL_PATH=""
    PANEL_LISTEN=""
    PANEL_CERT=""
    PANEL_KEY=""
    [[ -f "$DB" ]] && command -v sqlite3 >/dev/null 2>&1 || return 1
    local k v
    while IFS='|' read -r k v; do
        case "$k" in
            webPort)     PANEL_PORT="$v" ;;
            webBasePath) PANEL_PATH="$v" ;;
            webListen)   PANEL_LISTEN="$v" ;;
            webCertFile) PANEL_CERT="$v" ;;
            webKeyFile)  PANEL_KEY="$v" ;;
        esac
    done < <(sqlite3 -readonly "$DB" "SELECT key, value FROM settings WHERE key IN ('webPort','webBasePath','webListen','webCertFile','webKeyFile');" 2>/dev/null)
    PANEL_PORT="${PANEL_PORT:-2053}"
    PANEL_PATH="${PANEL_PATH:-/}"
    return 0
}

# Переводит дату UTC в секунды от 1970 года без запуска внешних программ (busybox date не понимает формат openssl).
# Параметры: год месяц день час минута секунда. Результат — в переменной UTC_EPOCH.
utc_epoch() {
    local y=$1 m=$((10#$2)) d=$((10#$3)) hh=$((10#$4)) mm=$((10#$5)) ss=$((10#$6))
    (( m <= 2 )) && y=$((y - 1))
    local era=$(( (y >= 0 ? y : y - 399) / 400 ))
    local yoe=$(( y - era * 400 ))
    local mp=$(( (m + 9) % 12 ))
    local doy=$(( (153 * mp + 2) / 5 + d - 1 ))
    local doe=$(( yoe * 365 + yoe / 4 - yoe / 100 + doy ))
    UTC_EPOCH=$(( (era * 146097 + doe - 719468) * 86400 + hh * 3600 + mm * 60 + ss ))
}

# Момент окончания сертификата (секунды от 1970 года, UTC). Параметр 1 — файл сертификата. Печатает число или ничего, если прочитать не удалось.
# Читать сертификат командой openssl при каждом открытии меню долго, поэтому результат кэшируется в $DIR_CACHE/cert_expiry
# и перечитывается, только если изменился путь к файлу или сам файл (он новее кэша).
cert_expiry_epoch() {
    local file="$1" cache="$DIR_CACHE/cert_expiry" cpath cexp out mon day tm year
    [[ -f "$file" ]] || return 1
    if [[ -f "$cache" && ! "$file" -nt "$cache" ]]; then
        IFS='|' read -r cpath cexp < "$cache"
        if [[ "$cpath" == "$file" && -n "$cexp" ]]; then
            echo "$cexp"
            return 0
        fi
    fi
    out=$(openssl x509 -enddate -noout -in "$file" 2>/dev/null)
    [[ "$out" == notAfter=* ]] || return 1
    # Формат: notAfter=Nov  5 12:00:00 2028 GMT
    read -r mon day tm year _ <<< "${out#notAfter=}"
    local months=" Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec" pre
    pre="${months%% $mon*}"
    [[ "$months" == *" $mon"* ]] || return 1
    local mnum=$(( $(wc -w <<< "$pre") + 1 ))
    IFS=: read -r hh mi ss <<< "$tm"
    utc_epoch "$year" "$mnum" "$day" "$hh" "$mi" "$ss"
    mkdir -p "$DIR_CACHE"
    echo "$file|$UTC_EPOCH" > "$cache"
    echo "$UTC_EPOCH"
}

# Печатает строки шапки главного меню: адрес панели и состояние SSL-сертификата (с цветной точкой).
# Данные берутся из базы панели (panel_settings_read); если базы или sqlite3 нет, ничего не печатает.
# Точка у сертификата: зелёная — осталось больше 30 дней, жёлтая — 30 дней и меньше, красная — истёк, не читается или нет файлов.
# Всегда возвращает 0, чтобы не обрывать цепочку команд в show_main_menu.
show_panel_info() {
    panel_settings_read || return 0
    local https=0 host="$PANEL_LISTEN" scheme="http"
    [[ -z "$host" || "$host" == "0.0.0.0" ]] && host="$(lan_ip)"
    if [[ -n "$PANEL_CERT" && -n "$PANEL_KEY" && -f "$PANEL_CERT" && -f "$PANEL_KEY" ]]; then
        https=1
        scheme="https"
    fi
    echo -e "Адрес панели:    ${scheme}://${host:-<IP роутера>}:${PANEL_PORT}${PANEL_PATH}"
    if [[ -z "$PANEL_CERT" ]]; then
        echo -e "SSL-сертификат:  не используется (панель по HTTP)"
    elif [[ $https -eq 0 ]]; then
        echo -e "SSL-сертификат:  файлы не найдены, панель работает по HTTP $(status_dot red)"
    else
        local exp now days
        exp=$(cert_expiry_epoch "$PANEL_CERT")
        printf -v now '%(%s)T' -1
        if [[ -z "$exp" ]]; then
            echo -e "SSL-сертификат:  срок действия не определён $(status_dot red)"
        else
            days=$(( (exp - now) / 86400 ))
            if (( exp <= now )); then
                echo -e "SSL-сертификат:  истёк $(status_dot red)"
            elif (( days <= 30 )); then
                echo -e "SSL-сертификат:  осталось $days дн. $(status_dot yellow)"
            else
                echo -e "SSL-сертификат:  осталось $days дн. $(status_dot green)"
            fi
        fi
    fi
    return 0
}

# Печатает красное предупреждение, если системное время роутера явно неверное (год раньше 2025).
# С неверным временем не работают HTTPS и выпуск сертификатов Let's Encrypt. Всегда возвращает 0.
show_time_warning() {
    local year
    printf -v year '%(%Y)T' -1
    if (( year < 2025 )); then
        echo -e "${color_red}Время на роутере неверно (год $year): HTTPS и сертификаты работать не будут. Проверьте синхронизацию времени.${style_plain}"
    fi
    return 0
}

# Печатает строку «Версия XRay:  x.x.x ●» для шапки главного меню (точка — статус версии, см. version_dot).
# Всегда возвращает 0, чтобы не обрывать цепочку команд в show_main_menu.
show_xray_version() {
    local v
    v=$(xray_version)
    if [[ "$CHECK_UPDATES" == true ]]; then
        echo -e "Версия XRay:     ${v:-не определена} $(version_dot "$v" "$LATEST_XRAY")"
    else
        echo -e "Версия XRay:     ${v:-не определена}"
    fi
    return 0
}

# Последняя версия Xray на GitHub (XTLS/Xray-core), например v25.8.3.
xray_last_version() {
    github_latest_tag XTLS/Xray-core 8
}

# Имя архива с ядром в релизах XTLS/Xray-core зависит от архитектуры процессора (переменная ARCHITECTURE).
# Результат — в XRAY_ZIP_NAME. Для неизвестной архитектуры возвращает 1.
xray_zip_name() {
    case "$ARCHITECTURE" in
        amd64) XRAY_ZIP_NAME="Xray-linux-64.zip" ;;
        386)   XRAY_ZIP_NAME="Xray-linux-32.zip" ;;
        arm64) XRAY_ZIP_NAME="Xray-linux-arm64-v8a.zip" ;;
        armv7) XRAY_ZIP_NAME="Xray-linux-arm32-v7a.zip" ;;
        armv6) XRAY_ZIP_NAME="Xray-linux-arm32-v6.zip" ;;
        armv5) XRAY_ZIP_NAME="Xray-linux-arm32-v5.zip" ;;
        s390x) XRAY_ZIP_NAME="Xray-linux-s390x.zip" ;;
        *) return 1 ;;
    esac
}

# Устанавливает ядро Xray указанной версии. Параметр 1 — тег релиза на GitHub (например, v25.8.3).
# Порядок действий: скачать архив, проверить контрольную сумму SHA-256, распаковать, пробно запустить новое ядро,
# остановить панель, заменить файл ядра (прежнее сохраняется как .bak), запустить панель снова (если она работала).
# Общая часть для пунктов «Обновить только XRay» и «Установить свою версию XRay».
xray_install_tag() {
    local last="$1" bin cur
    check_architecture 1
    if ! xray_zip_name; then
        logmsg "${color_red}${ICO_MAP[ERR]} Для архитектуры $ARCHITECTURE нет готового ядра Xray.${style_plain}"
        return 1
    fi
    bin=$(xray_bin_path)
    if [[ -z "$bin" ]]; then
        logmsg "${color_red}${ICO_MAP[ERR]} Файл ядра Xray не найден в $DIR_PROJECT/bin${style_plain}"
        return 1
    fi
    cur=$(xray_version)

    # Для распаковки архива нужна программа unzip
    if ! command -v unzip >/dev/null 2>&1; then
        logmsg "${color_green}${ICO_MAP[WORK]} Устанавливаю unzip...${style_plain}"
        opkg install unzip >/dev/null 2>&1
        if ! command -v unzip >/dev/null 2>&1; then
            logmsg "${color_red}${ICO_MAP[ERR]} Не удалось установить unzip.${style_plain}"
            return 1
        fi
    fi

    # --- скачивание ---
    local url="https://github.com/XTLS/Xray-core/releases/download/${last}/${XRAY_ZIP_NAME}"
    local work="$DIR_TMP/xray-update"
    local archive="$work/$XRAY_ZIP_NAME"
    rm -rf "$work"
    mkdir -p "$work"
    logmsg "${color_green}${ICO_MAP[WORK]} Скачиваю $XRAY_ZIP_NAME (${last})...${style_plain}"
    if ! curl -4 -fsSL -o "$archive" "$url"; then
        logmsg "${color_red}${ICO_MAP[ERR]} Не удалось скачать: $url${style_plain}"
        rm -rf "$work"
        return 1
    fi

    # --- проверка контрольной суммы (файл .dgst лежит рядом с архивом в релизе) ---
    local expected actual
    expected=$(curl -4 -fsSL "${url}.dgst" 2>/dev/null | grep -i '256' | grep -Eo '[0-9a-fA-F]{64}' | head -n1)
    if [[ -n "$expected" ]] && command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$archive" | awk '{print $1}')
        if [[ "${actual,,}" != "${expected,,}" ]]; then
            logmsg "${color_red}${ICO_MAP[ERR]} Контрольная сумма архива не совпала: файл повреждён или подменён. Обновление отменено.${style_plain}"
            rm -rf "$work"
            return 1
        fi
        logmsg "${color_green}${ICO_MAP[INF]} Контрольная сумма SHA-256 совпала.${style_plain}"
    else
        logmsg "${color_yellow}${ICO_MAP[WAR]} Не удалось проверить контрольную сумму (нет файла .dgst или программы sha256sum): продолжаю без проверки.${style_plain}"
    fi

    # --- распаковка: нужен только файл xray (в архиве ещё лежат geo-файлы, они не трогаются) ---
    unzip -o -q "$archive" xray -d "$work" 2>/dev/null || unzip -o -q "$archive" -d "$work" 2>/dev/null
    if [[ ! -f "$work/xray" ]]; then
        logmsg "${color_red}${ICO_MAP[ERR]} В архиве не найден файл xray.${style_plain}"
        rm -rf "$work"
        return 1
    fi
    chmod 755 "$work/xray"
    # Пробный запуск: убеждаемся, что новое ядро запускается на этом процессоре
    local newver
    newver=$("$work/xray" -version 2>/dev/null | head -n1 | awk '{print $2}')
    if [[ -z "$newver" ]]; then
        logmsg "${color_red}${ICO_MAP[ERR]} Новое ядро не запускается на этом роутере. Обновление отменено, старое ядро не тронуто.${style_plain}"
        rm -rf "$work"
        return 1
    fi

    # --- замена ядра ---
    local was_running=0
    check_status
    [[ $? == 0 ]] && was_running=1
    if [[ $was_running == 1 ]]; then
        stop
    fi
    # Ядро запускается панелью как отдельный процесс: на случай, если он остался, завершаем его
    pkill -f "$DIR_PROJECT/bin/xray-linux" 2>/dev/null
    cp -f "$bin" "$bin.bak"
    # Копируем в рабочий каталог под временным именем и переименовываем: так подмена файла происходит целиком
    if cp -f "$work/xray" "$bin.new" && chmod 755 "$bin.new" && mv -f "$bin.new" "$bin"; then
        # Кэш версии сбрасываем явно: на файловых системах с грубым временем изменения (например, FAT) сравнение времени могло бы не заметить замену
        rm -f "$DIR_CACHE/xray_version"
        logmsg "${color_green}${ICO_MAP[INF]} Ядро XRay обновлено: ${cur:-?} → ${newver}. Старая версия сохранена: $bin.bak${style_plain}"
    else
        logmsg "${color_red}${ICO_MAP[ERR]} Не удалось заменить файл ядра. Старое ядро осталось на месте.${style_plain}"
        rm -f "$bin.new"
    fi
    rm -rf "$work"
    # Запускаем панель снова, если она работала до обновления
    if [[ $was_running == 1 ]]; then
        start
    fi
    logmsg "${color_green}Сейчас установлена версия XRay: $(xray_version)${style_plain}"
}

# Пункт меню «Обновить только XRay»: обновляет ядро Xray до последней версии с GitHub (XTLS/Xray-core).
# Панель, настройки, клиенты и база данных не затрагиваются. Порядок действий:
#   1) сравнить установленную версию с последней;  2) скачать архив и проверить контрольную сумму SHA-256;
#   3) распаковать и пробно запустить новое ядро;  4) остановить панель, заменить файл ядра (старый сохраняется как .bak);
#   5) запустить панель снова (если она работала до обновления).
update_xray() {
    check_install || return 1
    check_architecture 1
    if ! xray_zip_name; then
        logmsg "${color_red}${ICO_MAP[ERR]} Для архитектуры $ARCHITECTURE нет готового ядра Xray.${style_plain}"
        return 1
    fi
    local bin cur last
    bin=$(xray_bin_path)
    if [[ -z "$bin" ]]; then
        logmsg "${color_red}${ICO_MAP[ERR]} Файл ядра Xray не найден в $DIR_PROJECT/bin${style_plain}"
        return 1
    fi
    cur=$(xray_version)
    logmsg "${color_green}${ICO_MAP[WORK]} Проверка последней версии XRay на GitHub (XTLS/Xray-core)...${style_plain}"
    last=$(xray_last_version)
    if [[ -z "$last" ]]; then
        logmsg "${color_red}${ICO_MAP[ERR]} Не удалось получить версию XRay, попробуйте позже${style_plain}"
        return 1
    fi
    if [[ "${last#v}" == "$cur" ]]; then
        logmsg "${color_green}Установлена последняя версия XRay: ${cur}${style_plain}"
        confirm_options "Переустановить XRay принудительно" "n"
        [[ $? == 0 ]] || return 0
    else
        logmsg "${color_yellow}Доступна новая версия XRay: ${last#v}, у вас: ${cur:-неизвестно}${style_plain}"
        confirm_options "Обновить XRay до ${last#v} (панель и настройки не пострадают). Продолжить" "y"
        [[ $? == 0 ]] || return 0
    fi
    xray_install_tag "$last"
}

# Пункт меню «Установить свою версию XRay»: ставит выбранную версию ядра (в том числе более старую, если новая не подошла).
# Версию вводит пользователь (например, 25.8.3). Архив берётся из релизов XTLS/Xray-core; если такой версии нет, скачивание не удастся,
# и старое ядро останется на месте. Проверка контрольной суммы и пробный запуск те же, что при обычном обновлении.
update_xray_custom() {
    check_install || return 1
    check_architecture 1
    if ! xray_zip_name; then
        logmsg "${color_red}${ICO_MAP[ERR]} Для архитектуры $ARCHITECTURE нет готового ядра Xray.${style_plain}"
        return 1
    fi
    local cur v
    cur=$(xray_version)
    confirm_options "Введите версию XRay (например, 25.8.3), сейчас стоит ${cur:-неизвестная}" "" "xray_custom_version" $color_cyan
    v="${map_confirm[xray_custom_version]}"
    v="${v#v}"
    if [[ ! "$v" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]]; then
        logmsg "${color_red}${ICO_MAP[ERR]} Неверный номер версии: '$v'. Нужен вид 25.8.3.${style_plain}"
        return 1
    fi
    if [[ "$v" == "$cur" ]]; then
        logmsg "${color_yellow}Версия XRay $v уже установлена.${style_plain}"
        confirm_options "Переустановить принудительно" "n"
        [[ $? == 0 ]] || return 0
    else
        confirm_options "Установить XRay $v вместо ${cur:-текущей}" "y"
        [[ $? == 0 ]] || return 0
    fi
    xray_install_tag "v$v"
}

# Пункт меню «Откатить XRay»: меняет местами текущее ядро и сохранённое прежнее (файл .bak, он остаётся после каждого обновления).
# Повторный откат возвращает всё назад. Панель на время замены останавливается и запускается снова, если она работала.
rollback_xray() {
    check_install || return 1
    local bin bak cur prev was_running=0
    bin=$(xray_bin_path)
    if [[ -z "$bin" ]]; then
        logmsg "${color_red}${ICO_MAP[ERR]} Файл ядра Xray не найден в $DIR_PROJECT/bin${style_plain}"
        return 1
    fi
    bak="$bin.bak"
    if [[ ! -f "$bak" ]]; then
        logmsg "${color_yellow}${ICO_MAP[WAR]} Прежняя версия не сохранена ($bak): откатывать нечего. Копия появляется после обновления XRay.${style_plain}"
        return 1
    fi
    cur=$(xray_version)
    prev=$("$bak" -version 2>/dev/null | head -n1 | awk '{print $2}')
    if [[ -z "$prev" ]]; then
        logmsg "${color_red}${ICO_MAP[ERR]} Прежнее ядро ($bak) не запускается, откат отменён.${style_plain}"
        return 1
    fi
    confirm_options "Вернуть XRay $prev (сейчас стоит ${cur:-неизвестная})" "y"
    [[ $? == 0 ]] || return 0
    check_status
    [[ $? == 0 ]] && was_running=1
    if [[ $was_running == 1 ]]; then
        stop
    fi
    pkill -f "$DIR_PROJECT/bin/xray-linux" 2>/dev/null
    # Меняем файлы местами через временное имя
    if mv -f "$bin" "$bin.swap" && mv -f "$bak" "$bin" && mv -f "$bin.swap" "$bak"; then
        rm -f "$DIR_CACHE/xray_version"
        logmsg "${color_green}${ICO_MAP[INF]} Откат выполнен: ${cur:-?} → ${prev}. Прежняя версия сохранена как $bak (повторный откат вернёт её обратно).${style_plain}"
    else
        logmsg "${color_red}${ICO_MAP[ERR]} Не удалось поменять файлы ядра местами. Проверьте каталог $DIR_PROJECT/bin${style_plain}"
    fi
    if [[ $was_running == 1 ]]; then
        start
    fi
    logmsg "${color_green}Сейчас установлена версия XRay: $(xray_version)${style_plain}"
}


# Сравнивает установленную версию панели с последней на GitHub (MHSanaei/3x-ui).
# Если вышла новая — предлагает переустановить панель (данные сохраняются).
update_panel(){
    check_install
    last_version_checked "$NAME_APP"
    if [[ "v$CURRENT_VERSION_PANEL" == "$LAST_VERSION_PANEL" ]]; then
        logmsg "${color_green}Установлена последняя версия $NAME_APP: v${CURRENT_VERSION_PANEL}${style_plain}"
    else
        logmsg "${color_yellow}Доступна новая версия $NAME_APP: ${LAST_VERSION_PANEL}, у вас: v${CURRENT_VERSION_PANEL}${style_plain}"
        confirm_options "Будет принудительно переустановлена последняя версия $NAME_APP, данные не пропадут. Продолжить"
        if [ $? == 0 ]; then
            logmsg "${color_bg_white}Начинаю обновление $NAME_APP..."
            install $NAME_APP $LAST_VERSION_PANEL $1
        fi
    fi
}

# То же для самого скрипта: версия берётся из x-ui.sh в репозитории SCRIPT_REPO (ветка main), файл скачивается оттуда же.
update_script(){
    check_install
    last_version_checked "script"
    if [[ -z "$LAST_VERSION_SCRIPT" ]]; then
        logmsg "${ICO_MAP[BAD]} ${color_red}Не удалось получить версию скрипта, попробуйте позже${style_plain}"
        return 1
    fi
    if [[ "$CURRENT_VERSION_SCRIPT" == "$LAST_VERSION_SCRIPT" ]]; then
        logmsg "${color_green}Установлена последняя версия скрипта: ${CURRENT_VERSION_SCRIPT}${style_plain}"
    else
        logmsg "${color_yellow}Доступна новая версия скрипта: ${LAST_VERSION_SCRIPT}, у вас: ${CURRENT_VERSION_SCRIPT}${style_plain}"
        confirm_options "Будет принудительно переустановлена последняя версия скрипта, данные не пропадут. Продолжить"
        if [ $? == 0 ]; then
            logmsg "${color_bg_white}Начинаю обновление скрипта..."
            SCRIPT_REF=main
            install script $LAST_VERSION_SCRIPT $1
        fi
    fi
}
            
# Обновляет и скрипт, и панель. Если скрипт обновился, дальше работает уже его новая версия.
update_all(){
    check_install
    if [[ -z $1 ]]; then
        update_script 1
        if [[ -n $it_was_updated ]]; then
            before_show_main_menu "$DIR_PROJECT_SHELL_SCRIPTS update_all 1 1"
        fi
    fi
    update_panel 1
    if [[ -n $it_was_updated ]]; then
        before_show_main_menu $DIR_PROJECT_SHELL_SCRIPTS
    fi
}

# Меню обновления: всё сразу / только скрипт / только панель / только XRay.
# С параметром --check (x-ui update --check) вместо меню просто проверяет наличие новых версий (см. check_updates).
update(){
    if [[ "$1" == "--check" ]]; then
        check_updates
        return $?
    fi
    check_install
    menu_choice menu_update "$1" "Выберите действие обновления"
    safe_call_function "$schoice"
}

# Узнаёт последнюю версию: для панели — на GitHub (MHSanaei/3x-ui), для скрипта — из строки CURRENT_VERSION_SCRIPT в x-ui.sh
# репозитория. Результат — в LAST_VERSION_PANEL / LAST_VERSION_SCRIPT. Возвращает 1, если версию только что запросили,
# и 0, если она уже была известна (или проверять нечего).
last_version_checked(){
    if [[ "$LAST_VERSION_SCRIPT" == "" && $1 == "script" ]]; then
        LAST_VERSION_SCRIPT=$(script_last_version)
        return 1
    fi
    if [[ "$LAST_VERSION_PANEL" == "" && $1 == "$NAME_APP" ]]; then
        LAST_VERSION_PANEL=$(panel_last_version)
        return 1
    fi
    return 0
}

# Скачивает панель (архив) или скрипт (один файл). Параметр 1 — что качаем, параметр 2 — приставка «v» к номеру версии.
# Если с первого раза не получилось, пробует тег с буквой v и без неё (на GitHub теги бывают v1.2.3 и 1.2.3).
download_proc() {
    check_architecture 1
    local version_type=$2
    local type="${1,,}"
    local version_to_check
    
    local outfile="$DIR_TMP/$SHELL_SHORT_NAME-$type.tar.gz"
    if [[ $type == "script" ]]; then
        version_to_check="${version_type}${LAST_VERSION_SCRIPT}"
        url="$SCRIPT_RAW/${SCRIPT_REF:-$version_to_check}/$SHELL_FULL_NAME"
        outfile="$DIR_TMP/$SHELL_SHORT_NAME-script.new"
    fi
    if [[ $type == "${NAME_APP,,}" ]]; then
        version_to_check="${version_type}${LAST_VERSION_PANEL}"
        url="https://github.com/MHSanaei/3x-ui/releases/download/${version_to_check}/x-ui-linux-${ARCHITECTURE}.tar.gz"
    fi
    
    # Скачиваем файл. Сертификат сайта проверяется (пакеты wget-ssl и ca-certificates ставятся в install_base).
    wget -O "$outfile" "${url}"
    local wget_rc=$?
    if [[ $wget_rc -eq 5 ]]; then
        # Код 5 у wget — не удалось проверить сертификат: повторять с другим тегом бессмысленно
        logmsg "${color_red}${ICO_MAP[ERR]} Не удалось проверить сертификат сайта загрузки. Проверьте дату и время на роутере и пакет ca-certificates (opkg install ca-certificates).${style_plain}"
        return 1
    fi
    if [[ $wget_rc -ne 0 ]]; then
        if [[ $version_to_check != v* && -z $version_type ]]; then
            logmsg "${ICO_MAP[GOOD]} Повторная попытка загрузки с ${color_magenta}v${style_plain}"
            download_proc $type "v"
            return $?
        elif [[ $version_to_check == v* && -z $version_type ]]; then
            logmsg "${ICO_MAP[GOOD]} Повторная попытка загрузки без ${color_magenta}v${style_plain}"
            download_proc $type ""
            return $?
        else 
            return 1
        fi
    else
        return 0
    fi
}

# Спрашивает подтверждение и очищает весь кэш скрипта.
clear_all_cache(){
    confirm_options "Вы действительно хотите удалить все файлы кэша"
    if [[ $? == 0 ]]; then
        clear_cache && logmsg "${ICO_MAP[GOOD]} ${color_green}Кэш полностью очищен.${style_plain}"
    fi
}

# Удаляет каталог кэша (сохранённые меню и версия панели).
clear_cache(){
    if [[ -d "$DIR_CACHE" ]]; then
        logmsg "${ICO_MAP[WORK]} ${color_green}Очистка кэша...${style_plain}"
        rm -rf "$DIR_CACHE" 2>/dev/null
    fi
}

# Главная функция установки.
# Параметры: 1 — что ставим (xui — панель, script — этот скрипт), 2 — версия (пусто = последняя),
# 3 — если задан, после установки не ждать Enter и не возвращаться в меню (так работает автоустановка).
# Для панели: качает архив, распаковывает, копирует в /opt/etc/x-ui, настраивает (при первой установке)
# и включает HTTPS самоподписанным сертификатом. Для скрипта: просто заменяет x-ui.sh новой версией.
install() {
    if check_status 2>/dev/null; [[ $? -eq 2 ]]; then
        # Панель ещё не установлена: проверяем систему и ставим нужные пакеты.
        check_os_release && install_base
    fi
    # Каталог new — метка «только что установлено». Если её нет, это обновление: останавливаем панель и чистим кэш.
    if [[ ! -d "$DIR_PROJECT/new" ]]; then
        # Перед обновлением панели делаем автоматическую копию базы данных (на случай, если новая версия что-то испортит)
        if [[ $1 == "$NAME_APP" && -f "$DB" ]]; then
            backup_auto "перед установкой панели"
        fi
        check_status
        if [[ $? == 0 ]]; then
            $SHELL_SHORT_NAME stop 1
        fi
        clear_cache && delete_config
    fi
    logmsg "${ICO_MAP[WORK]} ${color_green}Проверка доступности репозитория...${style_plain}"
    # Всё скачиваем и распаковываем во временном каталоге /opt/tmp.
    cd $DIR_TMP || return
    if [[ -z $2 ]]; then
        # Версия не указана — узнаём последнюю на GitHub.
        last_version_checked $1
    fi
    if [[ $1 == "$NAME_APP" ]]; then
        LAST_VERSION_PANEL=${LAST_VERSION_PANEL#v}
        if [[ -z "$2" ]]; then
            if [[ ! -n "$LAST_VERSION_PANEL" ]]; then
                logmsg "${ICO_MAP[BAD]} ${color_red}Не удалось получить версию $SHELL_SHORT_NAME, попробуйте позже${style_plain}"
                return
            fi
            logmsg "${ICO_MAP[GOOD]} Последняя версия $SHELL_SHORT_NAME: ${color_magenta}${LAST_VERSION_PANEL}${style_plain}, начинаю установку..."
            download_proc $1 "v"
            if [[ $? -ne 0 ]]; then
                logmsg "${ICO_MAP[BAD]} ${color_red}Не удалось скачать $SHELL_SHORT_NAME${style_plain}"
                return
            fi
        else
            LAST_VERSION_PANEL=$2
            logmsg "${ICO_MAP[WORK]} Начинаю установку ${color_magenta}$SHELL_SHORT_NAME $LAST_VERSION_PANEL${style_plain}"
            download_proc $1
            if [[ $? -ne 0 ]]; then
                logmsg "${ICO_MAP[BAD]} ${color_red}не удалось скачать $SHELL_SHORT_NAME $LAST_VERSION_PANEL, проверьте, что такая версия существует: ${url}${style_plain}"
                return
            fi
        fi
        # Распаковываем архив панели: появится каталог x-ui/ (панель) и каталог bin/ (ядро Xray).
        tar zxvf $SHELL_SHORT_NAME-"$1".tar.gz
        # Исполняемый файл панели называем xui, чтобы не путать его с командой x-ui (это наш скрипт).
        mv $SHELL_SHORT_NAME/$SHELL_SHORT_NAME $SHELL_SHORT_NAME/$NAME_APP
        # Для 32-битных ARM ядро Xray называется одинаково — xray-linux-arm.
        if [[ $ARCHITECTURE == "armv5" || $ARCHITECTURE == "armv6" || $ARCHITECTURE == "armv7" ]]; then
            mv bin/xray-linux-$ARCHITECTURE bin/xray-linux-arm
        fi
		# Файлы служб (systemd, OpenRC) на Entware не нужны.
		# ВАЖНО: x-ui.sh из архива панели — родной скрипт автора 3x-ui с интерпретатором /bin/bash (на Entware его нет).
		# Если его скопировать, он затрёт наш скрипт управления, и после обновления команда x-ui перестанет запускаться.
		rm -rf $DIR_TMP/$SHELL_SHORT_NAME/x-ui.service* $DIR_TMP/$SHELL_SHORT_NAME/x-ui.rc $DIR_TMP/$SHELL_SHORT_NAME/x-ui.sh 2>/dev/null
        chmod -R 755 $SHELL_SHORT_NAME/$NAME_APP
        # Копируем панель в рабочий каталог /opt/etc/x-ui.
        cp -rf $DIR_TMP/$SHELL_SHORT_NAME $DIR_MAIN
        if [[ ! -f $DB ]]; then
            # Базы данных ещё нет — это первая установка: задаём порт, логин, пароль и включаем HTTPS.
            # Если база есть — это обновление, достаточно обновить структуру базы (migration). Все настройки сохраняются.
            config_after_install
            ssl_enable_self_signed
        else
            migration
        fi
        logmsg "${ICO_MAP[GOOD]} ${color_green}$SHELL_SHORT_NAME $LAST_VERSION_PANEL${style_plain} установка завершена..."
        logmsg "Панель доступна по следующим адресам:${color_green}"
        view_panel
        # Переносим сам скрипт в /opt/etc/x-ui и создаём команду x-ui.
        check_all_ruls 1 2>/dev/null
        rm -rf $SHELL_SHORT_NAME 2>/dev/null
    elif [[ $1 == "script" ]]; then
        if [[ -z "$2" ]]; then
            if [[ ! -n "$LAST_VERSION_SCRIPT" ]]; then
                logmsg "${ICO_MAP[BAD]} ${color_red}Не удалось получить версию скрипта, попробуйте позже${style_plain}"
                return
            fi
            logmsg "${ICO_MAP[GOOD]} Последняя версия скрипта: ${LAST_VERSION_SCRIPT}, начинаю установку..."
            download_proc $1
            if [[ $? -ne 0 ]]; then
                logmsg "${ICO_MAP[BAD]} ${color_red}Не удалось скачать скрипт${style_plain}"
                return
            fi
        else
            LAST_VERSION_SCRIPT=$2
            logmsg "${ICO_MAP[WORK]} Начинаю установку скрипта ${color_magenta}$LAST_VERSION_SCRIPT${style_plain}"
            download_proc $1
            if [[ $? -ne 0 ]]; then
                logmsg "${ICO_MAP[BAD]} ${color_red}не удалось скачать скрипт $LAST_VERSION_SCRIPT, проверьте, что такая версия существует: ${url}${style_plain}"
                return
            fi
        fi
        # Проверяем, что скачан скрипт (первая строка начинается с #!), а не страница с ошибкой.
        if ! head -n 1 "$DIR_TMP/$SHELL_SHORT_NAME-script.new" | grep -q '^#!'; then
            logmsg "${ICO_MAP[BAD]} ${color_red}Скачанный файл не похож на скрипт: ${url}${style_plain}"
            rm -f "$DIR_TMP/$SHELL_SHORT_NAME-script.new"
            SCRIPT_REF=""
            return
        fi
        # Проверка контрольной суммы: рядом со скриптом в репозитории лежит файл x-ui.sh.sha256.
        # Если суммы нет (например, свой источник), только предупреждаем; если есть и не совпала — файл не устанавливаем.
        local expected actual
        expected=$(curl -4 -fsSL --max-time 10 "${url}.sha256" 2>/dev/null | awk '{print $1}' | head -n1)
        if [[ -n "$expected" ]] && command -v sha256sum >/dev/null 2>&1; then
            actual=$(sha256sum "$DIR_TMP/$SHELL_SHORT_NAME-script.new" | awk '{print $1}')
            if [[ "$actual" != "$expected" ]]; then
                logmsg "${color_red}${ICO_MAP[ERR]} Контрольная сумма скрипта не совпала, обновление отменено. Если файлы в репозитории только что обновлены, подождите 5 минут (кэш GitHub) и повторите.${style_plain}"
                rm -f "$DIR_TMP/$SHELL_SHORT_NAME-script.new"
                SCRIPT_REF=""
                return
            fi
            logmsg "${color_green}${ICO_MAP[INF]} Контрольная сумма скрипта совпала.${style_plain}"
        else
            logmsg "${color_yellow}${ICO_MAP[WAR]} Контрольную сумму скрипта проверить не удалось (нет файла .sha256 или программы sha256sum): продолжаю без проверки.${style_plain}"
        fi
        mv -f -- "$DIR_TMP/$SHELL_SHORT_NAME-script.new" $DIR_PROJECT_SHELL_SCRIPTS
        chmod +x $DIR_PROJECT_SHELL_SCRIPTS
        SCRIPT_REF=""
    else
        logmsg "${ICO_MAP[BAD]} ${color_red}Неизвестный тип установки: $1${style_plain}"
        return
    fi
    rm $SHELL_SHORT_NAME-"$1".tar.gz -f
    permissions
    logmsg "${ICO_MAP[GOOD]} ${style_reverse}$1: версия ${LAST_VERSION_PANEL} успешно установлена!${style_plain}"
    logmsg "${style_reverse}Для запуска скрипта введите: $DIR_INSTALL_LNK${style_plain}"
    # Ставим метку «только что установлено»: главное меню по ней предложит запустить панель и включить автозапуск.
    it_was_updated=1 && mkdir -p "$DIR_PROJECT/new"
    # Третий параметр не задан — ждём Enter и возвращаемся в меню (в автоустановке параметр задан, меню не нужно).
    if [[ -z $3 ]]; then
        before_show_main_menu $DIR_PROJECT_SHELL_SCRIPTS
    fi
}

# Установка конкретной версии. Параметры: 1 — что ставим, 2 — версия (если не задана, спросит), 3 — не возвращаться в меню.
custom() {
    if [[ -z "$2" ]]; then
        confirm_options "Введите версию $1 (например, 0.0.1)" "" "panel_version_$1"  $color_cyan
    else
        map_confirm["panel_version_$1"]=$2
    fi
    if [ -z "${map_confirm[panel_version_$1]}" ]; then
        echo "Версия панели не может быть пустой!"
		return 1
    fi
	install $1 "${map_confirm[panel_version_$1]}" "$3"
}

# Установка выбранной пользователем версии панели. Имя в нижнем регистре: так её вызывает меню (ключи пунктов приводятся к нижнему регистру).
install_custom_panel(){
    custom $NAME_APP "" 1
}

# Установка выбранной пользователем версии скрипта (версия = тег в репозитории, например 1.0.3 или v1.0.3).
install_custom_script(){
    custom script "" 1
}

# Меню «своя версия»: панель или скрипт.
install_custom(){
    menu_choice menu_install_custom "$1"
    safe_call_function "$schoice"
    if [[ -n $it_was_updated ]]; then
        before_show_main_menu $DIR_PROJECT_SHELL_SCRIPTS
    fi
}

# Полное удаление панели: останавливает её, убирает автозапуск, команду x-ui и каталог /opt/etc/x-ui. Спрашивает подтверждение.
# Резервные копии базы (каталог backup) по умолчанию переносятся в /opt/root/x-ui-backup, чтобы не пропасть вместе с панелью.
# Строка автопродления сертификата убирается из cron. Каталог acme.sh (/opt/etc/acme.sh) остаётся: его можно удалить вручную.
uninstall() {
    if [[ ! -f $DIR_PROJECT/$NAME_APP ]]; then
        logmsg "${color_red}Панель не установлена!${style_plain}"
        return
    fi
    confirm_options "Вы уверены, что хотите удалить панель" "n" "" "$color_red"
    [[ $? == 0 ]] || return
    logmsg "${color_yellow}Удаление... ${style_plain}"
    stop && disable
    # Резервные копии переносим за пределы каталога проекта, иначе они удалятся вместе с панелью
    local keep_dir=""
    if [[ -n "$(ls -A "$DIR_PROJECT/backup" 2>/dev/null)" ]]; then
        confirm_options "Сохранить резервные копии базы данных в $DIR_ENTWARE/root/x-ui-backup" "y"
        if [[ $? == 0 ]]; then
            keep_dir="$DIR_ENTWARE/root/x-ui-backup"
            [[ -e "$keep_dir" ]] && keep_dir="${keep_dir}-$(date +%Y%m%d%H%M%S)"
            mkdir -p "$DIR_ENTWARE/root" && mv "$DIR_PROJECT/backup" "$keep_dir" || keep_dir=""
        fi
    fi
    # Автопродление сертификата больше не нужно: убираем строку из cron
    if command -v crontab >/dev/null 2>&1 && crontab -l 2>/dev/null | grep -q 'acme.sh --cron'; then
        crontab -l 2>/dev/null | grep -v 'acme.sh --cron' | crontab -
        logmsg "${color_yellow}Автопродление сертификата убрано из cron${style_plain}"
    fi
    rm -rf "${DIR_AUTO_START:?}/$PRIORITY$SHELL_SHORT_NAME"
    rm -rf "${DIR_INSTALL_LNK:?}"
    rm -rf "${DIR_PROJECT:?}"
    logmsg "${color_yellow}Успешно удалено${style_plain}"
    [[ -n "$keep_dir" ]] && logmsg "${color_yellow}Резервные копии сохранены: $keep_dir${style_plain}"
    [[ -d "$DIR_ACME" ]] && logmsg "${color_yellow}Каталог acme.sh остался: $DIR_ACME (удалить: rm -rf $DIR_ACME)${style_plain}"
    logmsg "${color_yellow}Журнал сохранён в $DIR_LOGFILE!${style_plain}"
    logmsg "${color_yellow}Для удаления:${style_plain} ${color_magenta}rm -rf $DIR_LOGFILE${style_plain}"
    echo "$SHELL_SHORT_NAME удалён"
    exit 0
}

# Автоматическая установка без вопросов:
#   1. ставит последнюю версию панели;
#   2. создаёт самоподписанный сертификат и включает HTTPS;
#   3. задаёт случайные логин, пароль и путь к панели;
#   4. запускает панель и включает автозапуск;
#   5. в конце показывает адрес, логин и пароль (повторно они не показываются).
# Вызывается из стартового выбора или командой: x-ui.sh auto_install
auto_install() {
    check_uninstall || return 1
    logmsg "${ICO_MAP[WORK]} ${color_green}Автоматическая установка: последняя версия, HTTPS, случайные логин и пароль, автозапуск${style_plain}"
    AUTO_MODE=1
    AUTO_USER="$(random_string 8)"
    AUTO_PASS="$(random_string 16)"
    AUTO_PATH="/$(random_string 10)/"
    install "$NAME_APP" "" 1
    AUTO_MODE=0
    if [[ ! -x "$DIR_PROJECT/$NAME_APP" ]]; then
        logmsg "${color_red}${ICO_MAP[ERR]} Автоматическая установка не удалась. Подробности: $DIR_LOGFILE${style_plain}"
        return 1
    fi
    if [[ ! -f "$DIR_PROJECT_SHELL_SCRIPTS" ]]; then
        logmsg "${color_red}${ICO_MAP[ERR]} Не найден скрипт управления: $DIR_PROJECT_SHELL_SCRIPTS${style_plain}"
        return 1
    fi
    start && enable
    rm -rf "$DIR_PROJECT/new"
    local info port path ip scheme="http"
    info=$("$DIR_PROJECT/$NAME_APP" setting -show 2>/dev/null)
    port=$(echo "$info" | grep -Eo 'port: .+' | awk '{print $2}' | head -n1)
    path=$(echo "$info" | grep -Eo 'webBasePath: .+' | awk '{print $2}' | head -n1)
    ip=$(lan_ip)
    # Узнаём, по какому протоколу панель отвечает на самом деле, а не только по настройкам:
    # сначала пробуем HTTPS (ключ -k: самоподписанный сертификат не проверяем), затем HTTP; ждём запуск до 10 секунд.
    local answered=0 i
    if [[ -n "$ip" && -n "$port" ]] && command -v curl >/dev/null 2>&1; then
        for i in 1 2 3 4 5 6 7 8 9 10; do
            if curl -ksS -o /dev/null --max-time 3 "https://${ip}:${port}/" 2>/dev/null; then
                scheme="https"; answered=1; break
            elif curl -sS -o /dev/null --max-time 3 "http://${ip}:${port}/" 2>/dev/null; then
                scheme="http"; answered=1; break
            fi
            sleep 1
        done
    fi
    if [[ $answered -eq 0 ]]; then
        # Проверить не удалось (панель ещё запускается или нет curl): берём протокол из настроек
        ssl_cert_files_ok && scheme="https"
    elif [[ "$scheme" == "http" ]] && ssl_cert_files_ok; then
        logmsg "${color_yellow}${ICO_MAP[WAR]} Сертификат настроен, но панель отвечает по HTTP. Подробности: $DIR_LOGFILE${style_plain}"
    fi
    echo -e "\n###############################################\n"
    logmsg "${color_green}${ICO_MAP[GOOD]} $SHELL_SHORT_NAME установлена и запущена.${style_plain}"
    echo -e "Адрес:  ${color_green}${scheme}://${ip:-<IP роутера>}:${port:-2053}${path}${style_plain}"
    echo -e "Логин:  ${color_green}${AUTO_USER}${style_plain}"
    echo -e "Пароль: ${color_green}${AUTO_PASS}${style_plain}"
    if [[ "$scheme" == "https" ]]; then
        echo -e "\nБраузер предупредит о самоподписанном сертификате: это нормально, продолжите открытие страницы."
    fi
    echo -e "Сохраните данные: повторно они не показываются. Меню управления: ${color_yellow}$DIR_INSTALL_LNK${style_plain}"
    echo -e "Если команда $SHELL_SHORT_NAME «не найдена», выполните: export PATH=$DIR_ENTWARE/sbin:$DIR_ENTWARE/bin:\$PATH"
    echo -e "\n###############################################\n"
}
# END INSTALLATION ------------------------------------------------------------
# START PANEL COMMANDS ---------------------------------------------------------
# Раздел «Команды панели»: вопросы пользователю, настройки панели, сертификаты, запуск и остановка, база данных, резервные копии.
# Безопасно запускает внешнюю команду: если такой команды нет, пишет ошибку в журнал и возвращает 127, а не падает.
safe_call_command() {
    if [ $# -lt 1 ]; then
        logmsg "${color_red}${ICO_MAP[ERR]} Не указана команда для safe_call_command ${style_plain}"
        return 1
    fi
    local cmd="$1"; shift
    if ! declare -F "$cmd" > /dev/null 2>&1; then
        local t
        t=$(type -t -- "$cmd" 2>/dev/null || true)
        if [ -n "$t" ]; then
            "$cmd" "$@"
            return $?
        else
            if [[ -n "$DIR_LOGFILE" ]]; then
                local now
                now="$(date '+%Y-%m-%d %H:%M:%S')"
                local script_name="${0:-$NAME_REAL_SHELL}"
                local lineno="${BASH_LINENO[0]:-?}"
                local raw_err="${script_name}: строка ${lineno}: ${cmd}: команда не найдена"
                echo "[$now] [ERR] $raw_err" >> "$DIR_LOGFILE" 2>/dev/null
            fi
            logmsg "${color_red}${ICO_MAP[ERR]} $raw_err${style_plain}"
            return 127
        fi
    fi
}

# То же для функций скрипта (имя функции приходит из меню): если функции нет — ошибка в журнал, код 127.
safe_call_function() {
    if [ $# -lt 1 ]; then
        logmsg "${color_red}${ICO_MAP[ERR]} Не указана команда для safe_call_function${style_plain}"
        return 1
    fi
    local cmd="$1"; shift
    if declare -F "$cmd" > /dev/null 2>&1; then
        "$cmd" "$@"
        return $?
    else
        if [[ -n "$DIR_LOGFILE" ]]; then
            local now
            now="$(date '+%Y-%m-%d %H:%M:%S')"
            local script_name="${0:-$NAME_REAL_SHELL}"
            local lineno="${BASH_LINENO[0]:-?}"
            local raw_err="${script_name}: строка ${lineno}: ${cmd}: функция не найдена"
            echo "[$now] [ERR] $raw_err" >> "$DIR_LOGFILE" 2>/dev/null
        fi
        logmsg "${color_red}${ICO_MAP[ERR]} $raw_err${style_plain}"
        return 127
    fi
}

# Задаёт вопрос пользователю.
# Параметры: 1 — текст вопроса, 2 — значение по умолчанию (Enter = принять его),
# 3 — имя переменной для ответа (если задано, вопрос не «да/нет», а ввод значения: оно сохранится в map_confirm[имя]),
# 4 — цвет вопроса.
# Вопрос «да/нет» возвращает код 0 при согласии (y, д, да) и 1 при отказе.
# В автоматическом режиме (AUTO_MODE=1) вопрос не задаётся: берётся значение по умолчанию.
# Пароль не записывается в журнал.
confirm_options() {
    local question=$1
    local default=$2
    local confirm_type=""
    # Цвет текста вопроса (по умолчанию пурпурный).
    local txtcolor=${4:-$color_magenta}
    [[ "$3" == "config_password" || "$3" == "ssl_dns_var" ]] || logmsg "question: $question, default: $default, confirm_type: $confirm_type, txtcolor: $txtcolor" nolog
    [[ "$AUTO_MODE" == "1" ]] || echo ""
    # Третий параметр не задан — это вопрос «да/нет». Задан — нужно ввести значение, оно сохранится в map_confirm[$3].
    if [[ -z "$3" ]]; then
        confirm_type="[д/н]"
    fi
    local default_show="$default"
    if [[ -n "$confirm_type" ]]; then
        # Значение по умолчанию показываем по-русски: y → д, n → н.
        case "${default,,}" in
            y) default_show="д" ;;
            n) default_show="н" ;;
        esac
    fi
    if [[ "$AUTO_MODE" == "1" && -n "$default" ]]; then
        # Автоматический режим: ничего не спрашиваем, берём значение по умолчанию.
        temp="$default"
    elif [[ -n "$default" ]]; then
        echo -n -e "${txtcolor}$question $confirm_type? [по умолчанию: $default_show]:${style_plain}" && read -r -p " " temp
        if [[ "${temp}" == "" ]]; then
            temp=$default
        fi
    else
        echo -n -e "${txtcolor}$question $confirm_type?:${style_plain} " && read -r -p " " temp
    fi
    [[ "$3" == "config_password" || "$3" == "ssl_dns_var" ]] || logmsg "Choice: $temp" nolog
    if [[ -n "$confirm_type" ]]; then
        # Согласием считаем ответы y, yes, д, да (в любом регистре).
        case "$temp" in
            y|Y|yes|YES|Yes|д|Д|да|ДА|Да) return 0 ;;
            *) return 1 ;;
        esac
    else
        if [[ -n "$3" ]]; then
            map_confirm["$3"]="$temp"
        else
            logmsg "${color_red}${ICO_MAP[ERR]} Не указано имя переменной для сохранения ввода.${style_plain}"
            exit 1
        fi
    fi
}

# Спрашивает, перезапустить ли панель (после изменения настроек), и перезапускает.
confirm_restart() {
    confirm_options "Перезапустить службу $SHELL_SHORT_NAME" "y"
    if [[ $? == 0 ]]; then
        restart
    fi
}

# Сбрасывает логин и пароль администратора на случайные значения и показывает их.
reset_admin() {
    confirm_options "Вы уверены, что хотите сбросить учётные данные администратора к значениям по умолчанию" "n"
    if [[ $? == 0 ]]; then
        local usernameTemp=$(head -c 6 /dev/urandom | base64)
        local passwordTemp=$(head -c 6 /dev/urandom | base64)
        exe_set_admin "$usernameTemp" "$passwordTemp" "true"
        logmsg "${color_red}${ICO_MAP[INF]} Учётные данные администратора сброшены${style_plain}"
		show_admin "$usernameTemp" "$passwordTemp"
        confirm_restart
    fi
}

# Печатает логин (параметр 1) и пароль (параметр 2) в рамке.
show_admin() {
    echo -e "###############################################"
    echo -e "${color_green}Логин: ${1}${style_plain}"
    echo -e "${color_green}Пароль: ${2}${style_plain}"
    echo -e "###############################################"
}

# Спрашивает логин, пароль и нужно ли отключить двухфакторную защиту и сохраняет это в панели.
# Параметры 1–3 — значения по умолчанию. Если они не заданы, по умолчанию предлагаются случайные логин и пароль
# (в автоматическом режиме — AUTO_USER и AUTO_PASS), а не стандартные admin / 12345.
exe_set_admin() {
        confirm_options "Укажите логин" "${1:-${AUTO_USER:-$(random_string 8)}}" "config_account"  $color_cyan
        confirm_options "Укажите пароль" "${2:-${AUTO_PASS:-$(random_string 16)}}" "config_password" $color_cyan
		confirm_options "Отключить текущую двухфакторную аутентификацию (true/false)" "${3:-false}" "config_authentication" $color_cyan
        $DIR_PROJECT/$NAME_APP setting -username ${map_confirm[config_account]} -password ${map_confirm[config_password]} -resetTwoFactor ${map_confirm[config_authentication]}
		show_admin "${map_confirm[config_account]}" "${map_confirm[config_password]}"
}

# Пункт меню: задать логин и пароль администратора.
set_admin() {
    confirm_options "Вы уверены, что хотите задать учётные данные администратора" "n"
    if [[ $? == 0 ]]; then
        exe_set_admin
        logmsg "${color_red}${ICO_MAP[INF]} Учётные данные администратора заданы${style_plain}"
        confirm_restart
    fi
}

# Сбрасывает все настройки панели (порт, путь и т. д.) на значения по умолчанию. Логин и пароль не меняются.
reset_panel() {
    confirm_options "Вы уверены, что хотите сбросить все настройки панели. Данные учётной записи сохранятся: логин и пароль не изменятся" "n"
    if [[ $? == 0 ]]; then
        $DIR_PROJECT/$NAME_APP setting -reset
        logmsg "${ICO_MAP[INF]}Все настройки панели сброшены к значениям по умолчанию!" && view_panel && confirm_restart
    fi
}

# Перезапускает панель: останавливает, ждёт секунду, запускает и проверяет, что она работает.
restart() {
    $SHELL_SHORT_NAME stop 1 && sleep 1 && $SHELL_SHORT_NAME start 1 && sleep 1
    check_status; local status=$?
    [[ $status == 0 ]] && logmsg "${color_green}${ICO_MAP[INF]} $SHELL_SHORT_NAME успешно перезапущен${style_plain}" || logmsg "${color_red}${ICO_MAP[ERR]}Не удалось перезапустить $SHELL_SHORT_NAME, возможно, запуск занимает больше двух секунд. Проверьте журнал позже${style_plain}"
}

# Читает из панели пути к сертификату и ключу ОДНИМ запуском программы панели (она запускается долго).
# Результат — в переменных SSL_CERT_FILE и SSL_KEY_FILE (пусто, если не заданы).
# Команда «setting -getCert» печатает строки «cert: ...» и «key: ...» даже тогда, когда путей нет, поэтому берём то, что стоит после «cert:» / «key:».
ssl_cert_read() {
    local info
    info=$("$DIR_PROJECT/$NAME_APP" setting -getCert 2>/dev/null)
    SSL_CERT_FILE=$(echo "$info" | grep -Eo 'cert: .+' | awk '{print $2}' | head -n1)
    SSL_KEY_FILE=$(echo "$info" | grep -Eo 'key: .+' | awk '{print $2}' | head -n1)
}

# Настроен ли SSL-сертификат в панели: код 0 — да, 1 — нет.
ssl_cert_configured() {
    ssl_cert_read
    [[ -n "$SSL_CERT_FILE" ]]
}

# Работает ли SSL-сертификат на самом деле: пути заданы в панели И файлы сертификата и ключа существуют. Код 0 — да.
# Это важно: если пути заданы, а файлов нет, панель молча запускается по HTTP, хотя в настройках «сертификат есть».
ssl_cert_files_ok() {
    ssl_cert_read
    [[ -n "$SSL_CERT_FILE" && -n "$SSL_KEY_FILE" && -f "$SSL_CERT_FILE" && -f "$SSL_KEY_FILE" ]]
}

# Создаёт самоподписанный сертификат RSA 4096 для IP-адреса роутера в локальной сети (интерфейс br0)
# по стандартным путям $DIR_CERT/webCert.pem и webCertKey.pem. Код возврата — как у ssl_make_self_signed.
ssl_make_lan_self_signed() {
    local ip cn
    ip=$(lan_ip)
    cn="${ip:-$(hostname 2>/dev/null)}"
    cn="${cn:-$SHELL_SHORT_NAME}"
    logmsg "${color_green}${ICO_MAP[WORK]} Создание самоподписанного сертификата RSA 4096 для $cn (на роутере это может занять до минуты)...${style_plain}"
    ssl_make_self_signed rsa:4096 "$cn"
}

# Показывает, настроен ли SSL-сертификат панели, и по желанию задаёт его.
# Если файлов сертификата по указанным путям нет, для стандартных путей предлагает создать самоподписанный сертификат,
# а для чужих путей отказывается их прописывать (иначе панель молча работала бы по HTTP).
ssl_check(){
	local certs=$($DIR_PROJECT/$NAME_APP setting -getCert)
	if ! ssl_cert_configured; then
		logmsg "${color_yellow}SSL-сертификат сейчас не настроен!${style_plain}"
	else
		logmsg "${color_green}SSL-сертификат настроен:${style_plain}"
    	echo -e "\n###############################################\n"
    	echo -e "                 SSL В ПАНЕЛИ"
		logmsg "$certs"
    	echo -e "\n###############################################\n"
	fi

    confirm_options "Задать SSL-сертификат для панели" "n"
    if [[ $? == 0 ]]; then
    	local count=$(ls -1 "$DIR_CERT"/*.* 2>/dev/null | wc -l)
		if [[ $count -ge 2 ]]; then
			logmsg "Найдено файлов сертификатов: $count в $DIR_CERT/"
			ls -l "$DIR_CERT"
		fi
		confirm_options "Путь к публичному сертификату панели (webCert)" "$DIR_CERT/webCert.pem" "config_webCert" $color_cyan
		confirm_options "Путь к приватному ключу панели (webCertKey)" "$DIR_CERT/webCertKey.pem" "config_webCertKey" $color_cyan
		# Проверяем, что файлы существуют: панель не должна получить пути к несуществующим сертификатам
		local sc="${map_confirm[config_webCert]}" sk="${map_confirm[config_webCertKey]}"
		if [[ ! -f "$sc" || ! -f "$sk" ]]; then
			if [[ "$sc" == "$DIR_CERT/webCert.pem" && "$sk" == "$DIR_CERT/webCertKey.pem" ]]; then
				# Стандартные пути, но файлов ещё нет — предлагаем создать самоподписанный сертификат
				logmsg "${color_yellow}${ICO_MAP[WAR]} Файлов сертификата по этим путям пока нет.${style_plain}"
				confirm_options "Создать самоподписанный сертификат RSA 4096 по этим путям" "y"
				if [[ $? != 0 ]]; then
					logmsg "${color_yellow}${ICO_MAP[WAR]} Сертификат не задан: без файлов HTTPS не заработает.${style_plain}"
					return 1
				fi
				if ! ssl_make_lan_self_signed; then
					logmsg "${color_red}${ICO_MAP[ERR]} Не удалось создать сертификат.${style_plain}"
					return 1
				fi
			else
				# Свои пути: сами файлы мы создать не можем — просто сообщаем об ошибке
				logmsg "${color_red}${ICO_MAP[ERR]} Файл сертификата или ключа не найден: $sc, $sk. Сертификат не задан.${style_plain}"
				return 1
			fi
		fi
		local params=""
		[ -z "${map_confirm[config_webCert]}" ] || params="$params -webCert ${map_confirm[config_webCert]}"
		[ -z "${map_confirm[config_webCertKey]}" ] || params="$params -webCertKey ${map_confirm[config_webCertKey]}"
		logmsg "${color_yellow}Инициализация, подождите...${style_plain}"
		$DIR_PROJECT/$NAME_APP cert ${params}
		if ! ssl_cert_files_ok; then
			logmsg "${color_red}${ICO_MAP[ERR]} Панель не приняла сертификат: HTTPS не включён.${style_plain}"
			return 1
		fi
		echo -e "" && logmsg "${color_green}Инициализация завершена!${style_plain}"	
		return 0
	fi
	return 1
}

# Спрашивает порт, путь и IP-адрес, на котором панель слушает, и применяет настройки.
# Параметр 1 — не спрашивать про SSL. По умолчанию панель слушает адрес роутера в локальной сети (br0).
exe_set_panel() {
	confirm_options "Введите порт панели" "2053" "config_port" $color_cyan
	confirm_options "Введите путь к панели" "${AUTO_PATH:-/$(random_string 10)/}" "config_path" $color_cyan
	confirm_options "Введите IP-адрес для прослушивания" "$(lan_ip)" "config_listenIP" $color_cyan
	logmsg "${color_yellow}Инициализация, подождите...${style_plain}"
	local params=""
	[ -z "${map_confirm[config_port]}" ] || params="$params -port ${map_confirm[config_port]}"
	[ -z "${map_confirm[config_path]}" ] || params="$params -webBasePath ${map_confirm[config_path]}"
	[ -z "${map_confirm[config_listenIP]}" ] || params="$params -listenIP ${map_confirm[config_listenIP]}"
	# Применяем порт, путь и адрес прослушивания через программу панели.
	$DIR_PROJECT/$NAME_APP setting ${params}
	echo -e "" && logmsg "${color_green}Инициализация завершена!${style_plain}"
    if [[ -z $1 ]]; then
		confirm_options "Проверить и изменить SSL-сертификат" "n"
		if [[ $? -eq 0 ]]; then
			ssl_check
		fi
	fi
	return 0
}

# Пункт меню: изменить настройки панели.
set_panel() {
    confirm_options "Вы уверены, что хотите изменить настройки панели" "n"
    if [[ $? == 0 ]]; then
        exe_set_panel && confirm_restart
    fi
}

# Показывает текущие настройки панели и адреса доступа (https, если настроен сертификат).
view_panel() {
   local info=$("$DIR_PROJECT/$NAME_APP" setting -show)
    if [[ $? != 0 ]]; then
        logmsg "ошибка получения текущих настроек, проверьте журнал"
        return
    fi
	local existing_cert_path=$("$DIR_PROJECT/$NAME_APP" setting -getCert)
	local existing_ip=$($DIR_PROJECT/$NAME_APP setting -getListen | grep -Eo 'listenIP: .+' | awk '{print $2}')
    local existing_webBasePath=$(echo "$info" | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(echo "$info" | grep -Eo 'port: .+' | awk '{print $2}')
    local existing_cert=$(echo "$existing_cert_path" | grep -Eo 'cert: .+' | awk '{print $2}')
    local scheme="http"
    ssl_cert_files_ok && scheme="https"
    # Внешний IP роутера узнаём у сервиса ipify (запасной — ident.me).
    local server_ip=$(curl -s --max-time 3 https://api.ipify.org)
    if [ -z "$server_ip" ]; then
        server_ip=$(curl -s --max-time 3 https://4.ident.me)
    fi
    echo -e "\n###############################################\n"
	echo -e "IP-адрес прослушивания панели: $existing_ip\n"
	echo -e "$info\n"
	echo -e "$existing_cert_path\n"
    # Пути заданы, но файлов нет: панель в этом случае работает по HTTP
    if [[ -n "$existing_cert" && "$scheme" == "http" ]]; then
        logmsg "${color_red}${ICO_MAP[WAR]} Сертификат указан, но его файлов нет: панель работает по HTTP. Создайте сертификат (пункт 12) или уберите настройку (пункт 14).${style_plain}"
    fi
    if [[ "$scheme" == "https" ]]; then
        # Если сертификат лежит в каталоге с именем домена (cert/<домен>/), покажем адрес по домену.
        local domain=$(basename "$(dirname "$existing_cert")")

        if [[ "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            echo -e "${color_green}Адрес доступа: https://${domain}:${existing_port}${existing_webBasePath}${style_plain}\n"
        else
            echo -e "${color_green}Адрес доступа: https://${server_ip}:${existing_port}${existing_webBasePath}${style_plain}\n"
        fi
    else
        echo -e "${color_green}Адрес доступа: http://${server_ip}:${existing_port}${existing_webBasePath}${style_plain}\n"
    fi
	local localip=$(lan_ip)
	if [[ -n "$localip" ]]; then
		echo -e "${color_green}Локальный адрес доступа: ${scheme}://${localip}:${existing_port}${existing_webBasePath}${style_plain}\n"
	fi
    echo -e "###############################################"
}

# Запускает панель в фоне (если ещё не запущена) и проверяет, что процесс появился.
start() {
    check_status; local status=$?
    if [[ $status == 0 ]]; then
        echo ""
        logmsg "${color_green}${ICO_MAP[INF]} $SHELL_SHORT_NAME уже запущен, повторный запуск не требуется!${style_plain}"
    else
        tmpfile=$(mktemp)
        # Запускаем панель в фоне с повышенным приоритетом. Вывод сохраняем во временный файл и добавляем в журнал.
        nice -n -19 "$DIR_PROJECT/$NAME_APP" run >"$tmpfile" 2>&1 & disown
        output=$(cat "$tmpfile")
        echo "$output" >> "$DIR_LOGFILE"
        rm -f "$tmpfile"
        logmsg "${ICO_MAP[WORK]} загрузка..."
        sleep 1
        if ! check_panel; then
            logmsg "${ICO_MAP[BAD]} Ошибка: не удалось запустить $SHELL_SHORT_NAME"
        fi
        sleep 2
        check_status; local status2=$?
        [[ $status2 == 0 ]] && logmsg "${color_green}${ICO_MAP[INF]} $SHELL_SHORT_NAME успешно запущен${style_plain}" || logmsg "${color_red}${ICO_MAP[ERR]} не удалось запустить $SHELL_SHORT_NAME, возможно, запуск занимает больше двух секунд. Проверьте журнал позже${style_plain}"
    fi
}

# Останавливает панель: сначала обычное завершение, затем принудительное.
stop() {
    check_status; local status=$?
    if [[ $status == 1 ]]; then
        echo ""
        logmsg "${color_green}${ICO_MAP[INF]} $SHELL_SHORT_NAME уже остановлен, повторная остановка не требуется!${style_plain}"
    else
        # Сначала обычное завершение, затем принудительное (KILL).
        if killall $DIR_PROJECT/$NAME_APP 2>/dev/null; then
            killall -q -KILL $DIR_PROJECT/$NAME_APP
            logmsg "${ICO_MAP[GOOD]} $SHELL_SHORT_NAME остановлен"
        else
            logmsg "${ICO_MAP[GOOD]} $SHELL_SHORT_NAME уже был остановлен!"
        fi
        sleep 2
        check_status; local status2=$?
        [[ $status2 == 1 ]] && logmsg "${color_green}${ICO_MAP[INF]} $SHELL_SHORT_NAME успешно остановлен${style_plain}" || logmsg "${color_red}${ICO_MAP[ERR]}не удалось остановить $SHELL_SHORT_NAME, возможно, остановка занимает больше двух секунд. Проверьте журнал позже${style_plain}"
    fi
}

# Псевдоним для status.
check() {
	status
}

# Печатает, работает панель или остановлена. С параметром --json (x-ui status --json) печатает состояние в формате JSON
# для мониторинга и скриптов (см. status_json). Код возврата 0, если панель работает.
status() {
    if [[ "$1" == "--json" ]]; then
        status_json
        return $?
    fi
    if check_panel; then
        logmsg "${ICO_MAP[GOOD]}  $SHELL_SHORT_NAME работает"
    else
        logmsg "${ICO_MAP[GOOD]}  $SHELL_SHORT_NAME остановлен"
    fi
}

# Включает автозапуск: создаёт ссылку /opt/etc/init.d/S99x-ui на этот скрипт.
enable() {
    if [[ -L "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME" || -f "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME" ]]; then
        logmsg "${color_green}${ICO_MAP[INF]} Автозапуск $SHELL_SHORT_NAME уже включён${style_plain}"
    else
        # Автозапуск = символическая ссылка на этот скрипт в /opt/etc/init.d. Система вызовет её при загрузке роутера.
        ln -s "$DIR_PROJECT_SHELL_SCRIPTS" "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME"
        if [[ $? == 0 ]]; then
            logmsg "${color_green}${ICO_MAP[INF]} Автозапуск $SHELL_SHORT_NAME при загрузке успешно включён${style_plain}"
            dos2unix "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME" 2>/dev/null 
            chmod +x "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME" 2>/dev/null 
        else
            logmsg "${color_red}${ICO_MAP[ERR]} Не удалось включить автозапуск $SHELL_SHORT_NAME${style_plain}"
        fi
    fi
}

# Отключает автозапуск: удаляет ссылку из /opt/etc/init.d.
disable() {
    if [[ ! -L "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME" && ! -f "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME" ]]; then
        logmsg "${color_green}${ICO_MAP[INF]} Автозапуск $SHELL_SHORT_NAME уже отключён${style_plain}"
    else
        rm -rf "${DIR_AUTO_START:?}/$PRIORITY$SHELL_SHORT_NAME"
        if [[ $? == 0 ]]; then
            logmsg "${color_green}${ICO_MAP[INF]} Автозапуск $SHELL_SHORT_NAME успешно отключён${style_plain}"
        else
            logmsg "${color_red}${ICO_MAP[ERR]} Не удалось отключить автозапуск $SHELL_SHORT_NAME${style_plain}"
        fi
    fi
}

# Предлагает установить текстовый редактор (по умолчанию nano).
editor(){
        confirm_options "Рекомендуем редактор: $DEFAULT_EDITOR. Установить его" "y"
        if [[ $? == 0 ]]; then
            opkg install $DEFAULT_EDITOR
        fi
}

# Открывает в редакторе файл настроек скрипта ($DIR_CONFIG/settings).
edit_settings() {
    if [[ -f "$DIR_CONFIG/settings" ]]; then
        safe_call_command $DEFAULT_EDITOR $DIR_CONFIG/settings
        if [[ ! $? -eq 0 ]]; then
            logmsg "${color_yellow}${ICO_MAP[WAR]} Не удаётся открыть файл настроек в $DEFAULT_EDITOR.${style_plain}"
            editor && safe_call_command $DEFAULT_EDITOR $DIR_CONFIG/settings
        fi
    else
        logmsg "${color_red}Файл настроек не существует! ${style_plain}"
    fi
    logmsg "${color_red}${ICO_MAP[INF]} Путь к файлу настроек: $DIR_CONFIG/settings${style_plain}"
}

# Открывает в редакторе журнал скрипта.
log() {
    if [[ -f $DIR_LOGFILE ]]; then
        safe_call_command $DEFAULT_EDITOR $DIR_LOGFILE
        if [[ ! $? -eq 0 ]]; then
            logmsg "${color_yellow}${ICO_MAP[WAR]} Для просмотра журнала будет использован другой способ.${style_plain}"
            editor && safe_call_command $DEFAULT_EDITOR $DIR_LOGFILE
        fi
    else
        logmsg "${color_red}Файл журнала не существует! ${style_plain}"
    fi
    logmsg "${color_red}${ICO_MAP[INF]} Путь к файлу журнала: $DIR_LOGFILE${style_plain}"
}

# Состояние панели в виде кода возврата: 0 — работает, 1 — установлена, но остановлена, 2 — не установлена.
check_status() {
	if [[ ! -f "$DIR_PROJECT/$NAME_APP" ]]; then
		return 2
	fi
	if check_panel; then
		return 0
	else
		return 1
	fi
}

# Включён ли автозапуск (0 — да, 1 — нет).
check_enabled() {
    local temp=$(is-enabled)
    if [[ "${temp,,}" == "enabled" ]]; then
        return 0
    else
        return 1
    fi
}

# Разрешает действие, только если панель НЕ установлена (для установки). Иначе пишет ошибку.
check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
    logmsg "${color_red}${ICO_MAP[ERR]} Панель уже установлена. Чтобы установить другую или свою версию, сначала удалите текущую панель и $SHELL_SHORT_NAME.${style_plain}"
        return 1
    else
        return 0
    fi
}

# Разрешает действие, только если панель установлена (для управления). Иначе пишет ошибку.
check_install() {
    check_status
    if [[ $? == 2 ]]; then
        logmsg "${color_red}${ICO_MAP[ERR]} Сначала установите панель${style_plain}"
        return 1
    else
        return 0
    fi
}

# Печатает строку «Состояние: работает / не работает / не установлена» (и автозапуск).
show_status() {
    check_status
    case $? in
    0)
		logmsg "${color_black}${color_bg_white}Состояние ${SHELL_SHORT_NAME^^}:${style_plain} ${color_green}Работает${style_plain}"
        show_enable_status
        ;;
    1)
        logmsg "${color_black}${color_bg_white}Состояние ${SHELL_SHORT_NAME^^}:${style_plain} ${color_yellow}Не работает${style_plain}"
        show_enable_status
        ;;
    2)
        logmsg "${color_black}${color_bg_white}Состояние ${SHELL_SHORT_NAME^^}:${style_plain} ${color_red}Не установлена${style_plain}"
        ;;
    esac
}

# Печатает строку «Автозапуск: Да / Нет».
show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        logmsg "${color_black}${color_bg_white}Автозапуск $SHELL_SHORT_NAME:${style_plain} ${color_green}Да${style_plain}"
    else
        logmsg "${color_black}${color_bg_white}Автозапуск $SHELL_SHORT_NAME:${style_plain} ${color_red}Нет${style_plain}"
    fi
}

# Пункт меню: создать самоподписанный сертификат. Спрашивает тип ключа и имя (домен или IP), создаёт файлы
# в /opt/etc/x-ui/cert и по желанию применяет их к панели.
ssl() {
    confirm_options "Создать самоподписанный сертификат" "y"
    if [[ $? == 0 ]]; then
        if [[ ! -d $DIR_CERT ]]; then
            mkdir -p $DIR_CERT
        fi
    menu_choice menu_ssl "$1" "Выберите тип сертификата:"
    case ${schoice=$?,,} in
            ed25519)
                    key_opt="ed25519"
                ;;
            rsa_2048)
                    key_opt="rsa:2048"
                ;;
            rsa_4096)
                    key_opt="rsa:4096"
                ;;
            ecdsa_prime256v1)
                    key_opt="ec -pkeyopt ec_paramgen_curve:prime256v1"
                ;;
            ecdsa_secp384r1)
                    key_opt="ec -pkeyopt ec_paramgen_curve:secp384r1"
                ;;
            *)
                logmsg "${color_red}${ICO_MAP[ERR]} Неверный выбор! Результат: $schoice${style_plain}"
                return 1
                ;;
        esac
        confirm_options "Укажите доменное имя (DNS)" "example.com" "schoice_DNS"  $color_cyan
        cd $DIR_CERT || return
        logmsg "${color_green}${ICO_MAP[INF]} Создание самоподписанного сертификата ($schoice)...${style_plain}"
		ssl_make_self_signed "$key_opt" "${map_confirm[schoice_DNS]}"
        if [[ $? -eq 0 ]]; then
            chmod -R 600 "$DIR_CERT"
            logmsg "${color_green}${ICO_MAP[INF]} Самоподписанный сертификат успешно создан!${style_plain}"
			echo -e "\n###############################################\n"
			echo -e "                    ПУТИ SSL"
            logmsg "${color_green}${ICO_MAP[INF]} Путь к сертификату: $DIR_CERT/webCert.pem${style_plain}"
            logmsg "${color_green}${ICO_MAP[INF]} Путь к ключу: $DIR_CERT/webCertKey.pem${style_plain}"
			echo -e "\n###############################################\n"
			ssl_check
			if [[ $? == 0 ]]; then
				confirm_options "Проверить и изменить IP-адрес панели (РЕКОМЕНДУЕТСЯ!)" "y"
				if [[ $? == 0 ]]; then
					exe_set_panel 1
				fi
			fi
        else
            logmsg "${color_red}${ICO_MAP[ERR]} Не удалось создать самоподписанный сертификат.${style_plain}"
        fi
    fi
}

# Создаёт самоподписанный сертификат и кладёт файлы в /opt/etc/x-ui/cert (webCert.pem и webCertKey.pem).
# Параметры: 1 — тип ключа для openssl (по умолчанию rsa:4096; также rsa:2048, ec ..., ed25519), 2 — имя в сертификате (IP-адрес или домен).
# Что сделано для совместимости с браузерами:
#   • RSA вместо Ed25519 (многие браузеры не принимают сертификаты с ключом Ed25519);
#   • имя дублируется в subjectAltName (современные браузеры проверяют именно его, а не CN);
#   • сертификат помечен как конечный серверный (CA:FALSE, serverAuth);
#   • срок 825 дней: это максимум, который принимают iOS и macOS.
# Если установленный openssl не знает ключ -addext, пробуем с меньшим набором расширений.
ssl_make_self_signed() {
    local key_opt="${1:-rsa:4096}"
    local cn="$2"
    local san
    mkdir -p "$DIR_CERT"
    if [[ "$cn" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
        san="IP:$cn"
    else
        san="DNS:$cn"
    fi
    openssl req -x509 -nodes -sha256 -days 825 -newkey $key_opt \
        -keyout "$DIR_CERT/webCertKey.pem" -out "$DIR_CERT/webCert.pem" -subj "/CN=$cn" \
        -addext "subjectAltName=$san" -addext "basicConstraints=critical,CA:FALSE" \
        -addext "keyUsage=critical,digitalSignature,keyEncipherment" -addext "extendedKeyUsage=serverAuth" 2>/dev/null \
    || openssl req -x509 -nodes -sha256 -days 825 -newkey $key_opt \
        -keyout "$DIR_CERT/webCertKey.pem" -out "$DIR_CERT/webCert.pem" \
        -subj "/CN=$cn" -addext "subjectAltName=$san" 2>/dev/null \
    || openssl req -x509 -nodes -sha256 -days 825 -newkey $key_opt \
        -keyout "$DIR_CERT/webCertKey.pem" -out "$DIR_CERT/webCert.pem" \
        -subj "/CN=$cn" 2>/dev/null
    local rc=$?
    chmod 600 "$DIR_CERT/webCertKey.pem" "$DIR_CERT/webCert.pem" 2>/dev/null
    return $rc
}

# Включает HTTPS для панели самоподписанным сертификатом RSA 4096, если рабочего сертификата ещё нет.
# «Рабочий» — это когда пути заданы в панели И файлы по этим путям существуют. Если пути заданы, а файлов нет
# (панель в этом случае молча работает по HTTP), сертификат создаётся заново.
# Вызывается при первой установке до запуска панели. В обычном режиме спрашивает подтверждение (по умолчанию — да),
# в автоматическом создаёт сертификат без вопросов. Имя в сертификате — IP-адрес роутера в локальной сети.
ssl_enable_self_signed() {
    # Рабочий сертификат уже есть (например, его создали при настройке панели) — ничего не трогаем.
    # Пути читаются один раз: повторный запуск программы панели здесь не нужен.
    ssl_cert_read
    if [[ -n "$SSL_CERT_FILE" && -n "$SSL_KEY_FILE" && -f "$SSL_CERT_FILE" && -f "$SSL_KEY_FILE" ]]; then
        return 0
    fi
    if [[ -n "$SSL_CERT_FILE" ]]; then
        logmsg "${color_yellow}${ICO_MAP[WAR]} В панели указан сертификат, но файлов по этим путям нет: без них HTTPS не работает.${style_plain}"
    fi
    confirm_options "Создать самоподписанный сертификат и включить HTTPS для панели (рекомендуется)" "y"
    if [[ $? != 0 ]]; then
        logmsg "${color_yellow}${ICO_MAP[WAR]} HTTPS не включён: панель будет работать по HTTP.${style_plain}"
        return 0
    fi
    if ssl_make_lan_self_signed; then
        # Сообщаем панели пути к сертификату и ключу и проверяем, что она их приняла
        "$DIR_PROJECT/$NAME_APP" cert -webCert "$DIR_CERT/webCert.pem" -webCertKey "$DIR_CERT/webCertKey.pem"
        if ssl_cert_files_ok; then
            logmsg "${color_green}${ICO_MAP[INF]} HTTPS включён (самоподписанный сертификат: $DIR_CERT/webCert.pem).${style_plain}"
        else
            logmsg "${color_red}${ICO_MAP[ERR]} Панель не приняла сертификат: она будет работать по HTTP. Попробуйте задать его в меню (пункт про самоподписанный сертификат).${style_plain}"
        fi
    else
        logmsg "${color_red}${ICO_MAP[ERR]} Не удалось создать сертификат: панель будет работать по HTTP. Повторить можно в меню (пункт про самоподписанный сертификат).${style_plain}"
    fi
}

# Запускает acme.sh (клиент Let's Encrypt) с нашим рабочим каталогом.
acme_run() {
    "$(command -v sh)" "$DIR_ACME/acme.sh" --home "$DIR_ACME" "$@"
}

# Скачивает и устанавливает acme.sh в /opt/etc/acme.sh (последний релиз с GitHub, запасной вариант — ветка master).
# Параметр 1: слово dns — дополнительно поставить каталог dnsapi (модули для выпуска сертификата через API DNS-провайдера, ~1 МБ).
# Если нужное уже установлено, ничего не скачивает.
acme_install() {
    local need_dns=0
    [[ "$1" == "dns" ]] && need_dns=1
    if [[ -f "$DIR_ACME/acme.sh" && ( $need_dns -eq 0 || -d "$DIR_ACME/dnsapi" ) ]]; then
        return 0
    fi
    logmsg "${color_green}${ICO_MAP[WORK]} Устанавливаю acme.sh...${style_plain}"
    local tag url archive="$DIR_TMP/acme.sh.tar.gz" src="$DIR_TMP/acme-src"
    tag=$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/acmesh-official/acme.sh/releases/latest" 2>/dev/null | sed -n 's|.*/releases/tag/\(.*\)|\1|p')
    if [[ -n "$tag" ]]; then
        url="https://github.com/acmesh-official/acme.sh/archive/refs/tags/${tag}.tar.gz"
    else
        url="https://github.com/acmesh-official/acme.sh/archive/refs/heads/master.tar.gz"
    fi
    rm -rf "$src" "$archive"
    mkdir -p "$src" "$DIR_ACME"
    if ! curl -fsSL "$url" -o "$archive" || ! tar -xzf "$archive" -C "$src" --strip-components=1 || [[ ! -f "$src/acme.sh" ]]; then
        logmsg "${color_red}${ICO_MAP[ERR]} Не удалось скачать acme.sh: $url${style_plain}"
        rm -rf "$src" "$archive"
        return 1
    fi
    if [[ ! -f "$DIR_ACME/acme.sh" ]]; then
        cp "$src/acme.sh" "$DIR_ACME/acme.sh"
        # на Entware нет /usr/bin/env, поэтому прописываем интерпретатор явно
        sed -i "1s|^#!.*|#!$(command -v sh)|" "$DIR_ACME/acme.sh"
        chmod 700 "$DIR_ACME/acme.sh"
    fi
    if [[ $need_dns -eq 1 ]]; then
        if [[ ! -d "$src/dnsapi" ]]; then
            logmsg "${color_red}${ICO_MAP[ERR]} В архиве acme.sh нет каталога dnsapi.${style_plain}"
            rm -rf "$src" "$archive"
            return 1
        fi
        rm -rf "$DIR_ACME/dnsapi"
        cp -r "$src/dnsapi" "$DIR_ACME/dnsapi"
    fi
    rm -rf "$src" "$archive"
}

# Пункт меню: получить настоящий бесплатный сертификат Let's Encrypt для вашего домена.
# Два метода проверки домена: HTTP (домен указывает на внешний IP роутера, порт 80 свободен и открыт из интернета)
# или DNS через API вашего DNS-провайдера (порт 80 и публичный IP не нужны). Есть тестовый режим staging без лимитов.
# Скрипт проверяет домен, ставит acme.sh, получает сертификат, настраивает автопродление (cron)
# и по желанию применяет сертификат к панели.
ssl_domain() {
    echo -e "\n###############################################\n"
    echo -e "     SSL-СЕРТИФИКАТ ДЛЯ ВАШЕГО ДОМЕНА (Let's Encrypt)"
    echo -e "\n###############################################\n"
    logmsg "${color_yellow}${ICO_MAP[WAR]} Что нужно для выпуска сертификата:${style_plain}"
    echo -e "  1. Домен указывает на внешний IP-адрес роутера (нужен публичный, «белый» IP)."
    echo -e "  2. Порт 80 на роутере свободен и доступен из интернета: Let's Encrypt проверяет домен по HTTP."
    echo -e "     Если на порту 80 работает веб-интерфейс роутера, перенесите его на другой порт."
    echo -e "  3. В межсетевом экране роутера разрешён входящий TCP-порт 80 на время выпуска и продления."
    confirm_options "Продолжить" "y"
    if [[ $? != 0 ]]; then
        return 1
    fi

    confirm_options "Введите ваш домен (например, router.example.com)" "" "ssl_domain_name" $color_cyan
    local domain="${map_confirm[ssl_domain_name],,}"
    domain="${domain#http://}"
    domain="${domain#https://}"
    domain="${domain%%/*}"
    domain="${domain// /}"
    if [[ ! "$domain" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]]; then
        logmsg "${color_red}${ICO_MAP[ERR]} Неверное доменное имя: '${domain}'. Допустимы латинские буквы, цифры, дефис и точки (без http://, портов и символов подстановки *).${style_plain}"
        return 1
    fi

    # --- метод проверки домена и тестовый режим ---
    local method="http" server="letsencrypt" staging=0 dns_provider="" apply_default="y"
    confirm_options "Метод проверки домена: 1 — HTTP на порту 80 (нужен открытый порт 80), 2 — DNS через API вашего DNS-провайдера (порт 80 не нужен)" "1" "ssl_method" $color_cyan
    [[ "${map_confirm[ssl_method]}" == "2" ]] && method="dns"
    confirm_options "Тестовый режим Let's Encrypt (staging): без лимитов на число попыток, но браузеры такой сертификат не примут. Включить" "n"
    if [[ $? == 0 ]]; then
        staging=1
        server="letsencrypt_test"
        apply_default="n"
    fi

    if [[ "$method" == "dns" ]]; then
        # Для проверки через DNS acme.sh добавляет TXT-запись в вашей DNS-зоне через API провайдера: нужны код провайдера и ключи доступа.
        echo -e "Для проверки через DNS нужны код вашего DNS-провайдера в acme.sh и ключи доступа к его API."
        echo -e "Например, для Cloudflare: код dns_cf, переменная CF_Token=<токен>. Список провайдеров и нужных переменных:"
        echo -e "https://github.com/acmesh-official/acme.sh/wiki/dnsapi"
        confirm_options "Код DNS-провайдера (например, dns_cf)" "" "ssl_dns_provider" $color_cyan
        dns_provider="${map_confirm[ssl_dns_provider]}"
        if [[ ! "$dns_provider" =~ ^dns_[a-z0-9_]+$ ]]; then
            logmsg "${color_red}${ICO_MAP[ERR]} Неверный код провайдера: '$dns_provider'. Нужен вид dns_cf.${style_plain}"
            return 1
        fi
        # Переменные доступа вводятся строками вида ИМЯ=значение до пустой строки. Они передаются acme.sh и сохраняются им для продления.
        local dns_line
        while true; do
            confirm_options "Переменная доступа к API (ИМЯ=значение), пустая строка — закончить ввод" "" "ssl_dns_var" $color_cyan
            dns_line="${map_confirm[ssl_dns_var]}"
            [[ -z "$dns_line" ]] && break
            if [[ "$dns_line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.+)$ ]]; then
                export "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
            else
                logmsg "${color_yellow}${ICO_MAP[WAR]} Нужен вид ИМЯ=значение (например, CF_Token=abc123).${style_plain}"
            fi
        done
    else
        # --- проверки для метода HTTP (только предупреждения) ---
        local resolved public
        resolved=$(nslookup "$domain" 2>/dev/null | grep '^Address' | grep -v '#' | grep -Eo '([0-9]+\.){3}[0-9]+' | tail -n1)
        public=$(curl -4 -s --max-time 5 https://api.ipify.org 2>/dev/null)
        if [[ -z "$resolved" ]]; then
            logmsg "${color_yellow}${ICO_MAP[WAR]} Не удалось определить IP-адрес домена $domain. Проверьте, что DNS-запись создана.${style_plain}"
            confirm_options "Всё равно продолжить" "n"
            [[ $? == 0 ]] || return 1
        elif [[ -n "$public" && "$resolved" != "$public" ]]; then
            logmsg "${color_yellow}${ICO_MAP[WAR]} Домен указывает на $resolved, а внешний IP роутера: $public. Выпуск может не пройти.${style_plain}"
            confirm_options "Всё равно продолжить" "n"
            [[ $? == 0 ]] || return 1
        fi
        if command -v netstat >/dev/null 2>&1 && netstat -ltn 2>/dev/null | grep -Eq '[:.]80[[:space:]]'; then
            logmsg "${color_yellow}${ICO_MAP[WAR]} Порт 80 на роутере уже занят (например, веб-интерфейсом роутера). acme.sh не сможет его использовать.${style_plain}"
            confirm_options "Всё равно продолжить" "n"
            [[ $? == 0 ]] || return 1
        fi
    fi

    # --- зависимости и acme.sh ---
    logmsg "${color_green}${ICO_MAP[WORK]} Устанавливаю зависимости...${style_plain}"
    if [[ "$method" == "dns" ]]; then
        opkg install curl tar openssl-util ca-certificates >/dev/null 2>&1
        acme_install dns || return 1
    else
        opkg install curl tar openssl-util ca-certificates socat >/dev/null 2>&1
        if ! command -v socat >/dev/null 2>&1; then
            opkg update >/dev/null 2>&1
            opkg install curl tar openssl-util ca-certificates socat >/dev/null 2>&1
        fi
        if ! command -v socat >/dev/null 2>&1; then
            logmsg "${color_red}${ICO_MAP[ERR]} Не удалось установить socat (он нужен acme.sh для проверки по порту 80).${style_plain}"
            return 1
        fi
        acme_install || return 1
    fi

    # --- выпуск ---
    local force=""
    if [[ -d "$DIR_ACME/$domain" ]]; then
        confirm_options "Сертификат для $domain уже выпускался. Выпустить заново принудительно" "n"
        [[ $? == 0 ]] && force="--force"
    fi
    logmsg "${color_green}${ICO_MAP[WORK]} Запрашиваю сертификат для $domain...${style_plain}"
    if [[ "$method" == "dns" ]]; then
        acme_run --issue --dns "$dns_provider" -d "$domain" --server "$server" --log "$DIR_ACME/acme.sh.log" $force
    else
        acme_run --issue --standalone --httpport 80 -d "$domain" --server "$server" --log "$DIR_ACME/acme.sh.log" $force
    fi
    local rc=$?
    if [[ $rc -ne 0 && $rc -ne 2 ]]; then
        logmsg "${color_red}${ICO_MAP[ERR]} Не удалось получить сертификат (код $rc).${style_plain}"
        if [[ "$method" == "dns" ]]; then
            echo -e "  Частые причины: неверные ключи API или код провайдера, домен не входит в аккаунт провайдера,"
            echo -e "  не успела обновиться DNS-запись, превышен лимит запросов Let's Encrypt."
        else
            echo -e "  Частые причины: порт 80 закрыт или занят, домен указывает не на этот роутер,"
            echo -e "  у провайдера нет публичного IP-адреса, превышен лимит запросов Let's Encrypt."
        fi
        echo -e "  Подробности: $DIR_ACME/acme.sh.log"
        return 1
    fi

    # --- установка файлов (путь вида cert/<домен>/ нужен, чтобы панель показала https://<домен>) ---
    mkdir -p "$DIR_CERT/$domain"
    acme_run --install-cert -d "$domain" \
        --fullchain-file "$DIR_CERT/$domain/fullchain.pem" \
        --key-file "$DIR_CERT/$domain/privkey.pem" \
        --reloadcmd "PATH=$DIR_ENTWARE/sbin:$DIR_ENTWARE/bin:\$PATH $DIR_ENTWARE/bin/bash $DIR_PROJECT_SHELL_SCRIPTS restart"
    if [[ $? -ne 0 ]]; then
        logmsg "${color_red}${ICO_MAP[ERR]} Не удалось установить сертификат в $DIR_CERT/$domain/${style_plain}"
        return 1
    fi
    chmod 600 "$DIR_CERT/$domain"/*.pem 2>/dev/null
    logmsg "${color_green}${ICO_MAP[INF]} Сертификат получен!${style_plain}"
    echo -e "\n###############################################\n"
    echo -e "                    ПУТИ SSL"
    logmsg "${color_green}${ICO_MAP[INF]} Путь к сертификату: $DIR_CERT/$domain/fullchain.pem${style_plain}"
    logmsg "${color_green}${ICO_MAP[INF]} Путь к ключу: $DIR_CERT/$domain/privkey.pem${style_plain}"
    echo -e "\n###############################################\n"

    # --- автопродление (сертификат живёт 90 дней) ---
    if command -v crontab >/dev/null 2>&1; then
        local cron_line="17 3 * * * $(command -v sh) $DIR_ACME/acme.sh --cron --home $DIR_ACME >/dev/null 2>&1"
        (crontab -l 2>/dev/null | grep -v 'acme.sh --cron'; echo "$cron_line") | crontab -
        logmsg "${color_green}${ICO_MAP[INF]} Автопродление добавлено в cron (ежедневная проверка в 03:17).${style_plain}"
        echo -e "  Для работы автопродления должна быть запущена служба cron."
    else
        logmsg "${color_yellow}${ICO_MAP[WAR]} Планировщик cron не найден: автопродления не будет. Сертификат действует 90 дней.${style_plain}"
        echo -e "  Установите cron (в Entware обычно: opkg install cron) и запустите этот пункт ещё раз,"
        echo -e "  либо продлевайте вручную: $SHELL_SHORT_NAME ssl_domain"
    fi

    # --- применение к панели ---
    if [[ $staging -eq 1 ]]; then
        logmsg "${color_yellow}${ICO_MAP[WAR]} Это ТЕСТОВЫЙ сертификат: браузеры ему не доверяют. Для настоящего повторите выпуск без тестового режима (ответьте «да» на вопрос о принудительном выпуске).${style_plain}"
    fi
    confirm_options "Применить сертификат к панели" "$apply_default"
    if [[ $? == 0 ]]; then
        "$DIR_PROJECT/$NAME_APP" cert -webCert "$DIR_CERT/$domain/fullchain.pem" -webCertKey "$DIR_CERT/$domain/privkey.pem"
        restart
        local info=$("$DIR_PROJECT/$NAME_APP" setting -show 2>/dev/null)
        local p_port=$(echo "$info" | grep -Eo 'port: .+' | awk '{print $2}' | head -n1)
        local p_path=$(echo "$info" | grep -Eo 'webBasePath: .+' | awk '{print $2}' | head -n1)
        echo -e "\n###############################################\n"
        logmsg "${color_green}${ICO_MAP[INF]} Адрес доступа: https://${domain}:${p_port}${p_path}${style_plain}"
        echo -e "\n###############################################\n"
        echo -e "  По умолчанию панель слушает только адрес роутера в локальной сети."
        echo -e "  Чтобы открывать её по домену из интернета, измените IP прослушивания в пункте"
        echo -e "  «Изменить настройки панели» и откройте порт панели в межсетевом экране роутера."
    fi
}

# Пункт меню: удалить SSL-сертификат из настроек панели, чтобы она снова работала по HTTP.
# Порядок действий: штатный сброс (cert -reset) → пустые пути → правка базы данных (запасной вариант).
# Файлы самоподписанного сертификата можно удалить тоже. Сертификаты, полученные для домена (cert/<домен>/), не затрагиваются.
ssl_remove() {
    local bin="$DIR_PROJECT/$NAME_APP"
    # Если сертификата в панели нет — делать нечего
    if ! ssl_cert_configured; then
        logmsg "${color_yellow}${ICO_MAP[WAR]} SSL-сертификат в панели не настроен: она уже работает по HTTP.${style_plain}"
        return 0
    fi
    logmsg "${color_yellow}Сейчас в панели настроен сертификат:${style_plain}"
    "$bin" setting -getCert
    confirm_options "Удалить SSL-сертификат из панели и вернуться к HTTP" "n" "" "$color_red"
    if [[ $? != 0 ]]; then
        return 0
    fi
    # 1. Штатный сброс сертификата
    "$bin" cert -reset >/dev/null 2>&1
    # 2. Если не помогло — задаём пустые пути к сертификату и ключу
    if ssl_cert_configured; then
        "$bin" cert -webCert "" -webCertKey "" >/dev/null 2>&1
    fi
    # 3. Запасной вариант: очищаем значения прямо в базе данных панели
    if ssl_cert_configured && [[ -f "$DB" ]] && command -v sqlite3 >/dev/null 2>&1; then
        sqlite3 "$DB" "UPDATE settings SET value='' WHERE key IN ('webCertFile','webKeyFile');" 2>/dev/null
    fi
    if ssl_cert_configured; then
        logmsg "${color_red}${ICO_MAP[ERR]} Не удалось убрать сертификат автоматически. Очистите пути к сертификату в самой панели (Настройки панели → Сертификат).${style_plain}"
        return 1
    fi
    logmsg "${color_green}${ICO_MAP[INF]} SSL-сертификат удалён из настроек панели: после перезапуска она будет работать по HTTP.${style_plain}"
    # Файлы самоподписанного сертификата больше не нужны — предлагаем удалить
    if [[ -f "$DIR_CERT/webCert.pem" || -f "$DIR_CERT/webCertKey.pem" ]]; then
        confirm_options "Удалить также файлы самоподписанного сертификата (webCert.pem, webCertKey.pem)" "y"
        if [[ $? == 0 ]]; then
            rm -f "$DIR_CERT/webCert.pem" "$DIR_CERT/webCertKey.pem"
            logmsg "${color_green}${ICO_MAP[INF]} Файлы сертификата удалены.${style_plain}"
        fi
    fi
    echo -e "Сертификаты, полученные для вашего домена (каталог cert/<домен>), и их автопродление не затрагиваются."
    # Перезапуск нужен, чтобы панель перешла на HTTP
    confirm_restart
    view_panel
}

# Работает ли панель: ищет запущенный процесс с именем xui. Код 0 — работает.
# Ищется точное имя процесса (pgrep -x), а не любая строка xui в командной строке: иначе «работающей» считалась бы и сторонняя программа,
# у которой в параметрах встретилось xui.
check_panel() {
    pgrep -x "$NAME_APP" > /dev/null
}

# Печатает слово enabled, если автозапуск включён (есть ссылка в /opt/etc/init.d).
is-enabled() {
	if [[ -L "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME" || -f "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME" ]]; then
		echo "enabled"
	fi 
}

# Собирает текст меню с номерами из текста вида:
#     ключ::Русский текст   — пункт (ключ — имя функции, которую вызовет выбор)
#     [br]                  — горизонтальная линия-разделитель
# Результат: menu_numeric_choice_list (готовый вывод), start_index/max_num_of_choices (диапазон номеров),
# menu_key_list (соответствие «номер:ключ»). Готовое меню кэшируется в /opt/etc/x-ui/cache/menu.
menu_numeric_choice(){
# Имя переменной с текстом меню (или сам текст, если передан второй параметр).
local name_menu=${2:-"$1"}
local cache=$2
menu_numeric_choice_list=""
# menu_key_list хранит строки «номер:ключ». По нему потом определяется функция выбранного пункта.
menu_key_list=""
if [[ -d "$DIR_CACHE/menu" && ! -f "$DIR_CACHE/.menu_$MENU_HASH" ]]; then
    rm -rf "$DIR_CACHE/menu" "$DIR_CACHE"/.menu_*
fi
if [[ -z "$2" ]]; then
    local menu="${!name_menu}"
else
    local menu="$1"
fi
if [[ -f "$DIR_CACHE/menu/$name_menu" && -z $no_cache_needed ]]; then
    source "$DIR_CACHE/menu/$name_menu"
    logmsg "CACHED MENU: $name_menu" nolog
else
    # Разбиваем текст меню на строки: по одной строке на пункт.
    IFS=$'\n' read -r -d '' -a menu_arr <<< "$menu"$'\0'
    max_num_of_choices=1
    menu_numeric_choice_br_list="————————————————————————————————————————
    "
    menu_numeric_choice_list="    $menu_numeric_choice_br_list"
    for i in "${!menu_arr[@]}"; do
        if [[ $i != 0 ]]; then
            max_num_of_choices=$((max_num_of_choices+1))
        else
            start_index=$max_num_of_choices
        fi
        # Строка [br] — горизонтальная линия. Она не получает номера.
        if [[ ${menu_arr[$i]} == "[br]" ]]; then
            menu_numeric_choice_list+="${menu_numeric_choice_br_list}"
            max_num_of_choices=$((max_num_of_choices-1))
        else
    # Пункт записан как «ключ::Русский текст»: ключ отделяем и запоминаем, на экране показываем только текст.
    local item_label="${menu_arr[$i]}"
    if [[ "$item_label" == *"::"* ]]; then
        menu_key_list+="${max_num_of_choices}:${item_label%%::*}"$'\n'
        item_label="${item_label#*::}"
    fi
    menu_numeric_choice_list+="${color_blue}($max_num_of_choices)${style_plain}$([[ $max_num_of_choices -lt 10 ]] && echo "  " || echo " ")[${item_label}]
    "
        fi
    done
    menu_numeric_choice_list+="$menu_numeric_choice_br_list"
    # Сохраняем собранное меню в кэш, чтобы в следующий раз не собирать заново. Кэш привязан к тексту меню (MENU_HASH): после любого изменения меню он обновляется сам.
    if [[ -z $cache && -z $no_cache_needed ]]; then
        if [[ ! -d "$DIR_CACHE/menu" ]]; then
            mkdir -p "$DIR_CACHE/menu"
            touch "$DIR_CACHE/.menu_$MENU_HASH"
        fi
        echo -e "menu_numeric_choice_list=\"$menu_numeric_choice_list\"" >> "$DIR_CACHE/menu/$name_menu"
        echo -e "start_index=\"$start_index\"" >> "$DIR_CACHE/menu/$name_menu"
        echo -e "max_num_of_choices=\"$max_num_of_choices\"" >> "$DIR_CACHE/menu/$name_menu"
        echo -e "menu_key_list=\"$menu_key_list\"" >> "$DIR_CACHE/menu/$name_menu"
    fi
fi
}

declare -A ext_map_zip=( [gzip]=".gz" [bzip2]=".bz2" [xz]=".xz" [zstd]=".zst" [cp]="" )
# Создаёт резервную копию базы данных панели с выбранным способом сжатия (zstd, gzip, bzip2, xz или без сжатия).
# Копии лежат в /opt/etc/x-ui/backup/db.
backup(){
    if [[ ! -d "$DIR_PROJECT/backup/db" ]]; then
        mkdir -p "$DIR_PROJECT/backup/db"
    fi
    # Дата и время входят в имя файла копии.
    now=$(date +"%Y_%m_%d_%H_%M_%S")
    filename="backup_$now.db"
    menu_choice menu_archive "$1" "Выберите способ сжатия" "no_compression"
    if ! command -v $schoice >/dev/null 2>&1; then
        confirm_options "Утилита сжатия '$schoice' не установлена. Установить её" "y" "" $color_red
            if [[ $? == 0 ]]; then
                logmsg "Установка утилиты сжатия: $schoice"
                opkg update && opkg install "$schoice"
            else
                logmsg "Операция отменена. Резервная копия не создана."
                return 1
            fi
    fi
    case ${schoice=$?,,} in
        cp)
            safe_call_command "$schoice" "$DB" "$DIR_PROJECT/backup/db/$filename${ext_map_zip[$schoice]}"
            ;;
        *)
            if [[ -n ${ext_map_zip[$schoice]} ]]; then
                safe_call_command "$schoice" "${ext_map_zip[$schoice]:+"-c"}" "$DB" > "$DIR_PROJECT/backup/db/$filename${ext_map_zip[$schoice]}"
            else
                logmsg "${color_red}${ICO_MAP[ERR]} Неподдерживаемый способ сжатия${style_plain}"
                return 1
            fi
            ;;
    esac
    local tmpfile=$(ls -1 $DIR_PROJECT/backup/db/$filename* 2>/dev/null)
    if [[ -n $tmpfile ]]; then
        logmsg "${color_green}${ICO_MAP[INF]} Резервная копия создана ($schoice): $DIR_PROJECT/backup/db/$filename${style_plain}"
    else
        logmsg "${color_red}${ICO_MAP[ERR]} Не удалось создать резервную копию!${style_plain}"
    fi
    echo -e "" && logmsg "Доступные резервные копии:" && echo -e ""
    ls -1 "$DIR_PROJECT/backup/db/"
    echo -e ""
}

# Удаляет старые резервные копии, оставляя указанное количество самых свежих.
delete_old_backups(){
    if [ ! "$(ls -A "$DIR_PROJECT/backup/db")" ]; then
        logmsg "${color_red}${ICO_MAP[ERR]} Резервные копии не найдены.${style_plain}"
    else
        echo -e "" && logmsg "Доступные резервные копии:" && echo -e ""
        ls -1 "$DIR_PROJECT/backup/db/"
        echo -e ""
        confirm_options "Сколько последних резервных копий оставить? Введите число" "100500" "num_keep"  $color_cyan
        if [[ ${map_confirm[num_keep]} =~ ^[0-9]+$ ]]; then
            ls -1t $DIR_PROJECT/backup/db | tail -n +$((${map_confirm[num_keep]} + 1)) | xargs -I{} rm -- "$DIR_PROJECT/backup/db/{}"
            echo -e "" && logmsg "Доступные резервные копии:" && echo -e ""
            ls -1 "$DIR_PROJECT/backup/db/"
            echo -e ""
        else
            logmsg "${color_red}${ICO_MAP[ERR]} Введено неверное число!${style_plain}"
        fi	
    fi
}

# Автоматическая резервная копия базы данных без вопросов: её вызывают cron (команда x-ui backup_auto) и установка панели перед обновлением.
# Параметр 1 — причина (попадает в сообщение). Файл: /opt/etc/x-ui/backup/db/auto_ГГГГ_ММ_ДД_чч_мм_сс.db.gz (без gzip — .db).
# Копия делается командой sqlite3 .backup: это целостный снимок, даже если панель в этот момент пишет в базу (без sqlite3 — обычное копирование).
# Хранятся последние BACKUP_KEEP автоматических копий, ручные копии (меню «Управление резервными копиями») не трогаются.
# Восстановить копию можно тем же пунктом меню, что и ручную.
backup_auto() {
    local reason="${1:-по расписанию}" dir="$DIR_PROJECT/backup/db" now out tmp keep old
    if [[ ! -f "$DB" ]]; then
        logmsg "${color_yellow}${ICO_MAP[WAR]} Базы данных нет: резервная копия не создана.${style_plain}"
        return 1
    fi
    mkdir -p "$dir"
    printf -v now '%(%Y_%m_%d_%H_%M_%S)T' -1
    tmp="$dir/.auto_$now.tmp"
    if ! { command -v sqlite3 >/dev/null 2>&1 && sqlite3 "$DB" ".backup '$tmp'" 2>/dev/null; }; then
        cp -f "$DB" "$tmp" || return 1
    fi
    if command -v gzip >/dev/null 2>&1 && gzip -c "$tmp" > "$dir/auto_$now.db.gz"; then
        out="$dir/auto_$now.db.gz"
        rm -f "$tmp"
    else
        out="$dir/auto_$now.db"
        mv -f "$tmp" "$out"
    fi
    chmod 600 "$out"
    # Оставляем только последние BACKUP_KEEP автоматических копий
    keep="${BACKUP_KEEP:-10}"
    [[ "$keep" =~ ^[0-9]+$ ]] || keep=10
    ls -1t "$dir"/auto_* 2>/dev/null | tail -n +$((keep + 1)) | while IFS= read -r old; do
        rm -f "$old"
    done
    logmsg "${color_green}${ICO_MAP[INF]} Резервная копия базы создана ($reason): $out${style_plain}"
}

# Пункт меню: включить или выключить автоматические резервные копии по расписанию (cron).
# Расписание: раз в неделю, по воскресеньям в 04:30; хранятся последние BACKUP_KEEP копий (см. backup_auto).
# Нужен планировщик cron (в Entware пакет cron) и запущенная служба cron.
backup_cron() {
    if ! command -v crontab >/dev/null 2>&1; then
        logmsg "${color_red}${ICO_MAP[ERR]} Нет планировщика cron. Установите его: opkg install cron${style_plain}"
        return 1
    fi
    local line="30 4 * * 0 PATH=$DIR_ENTWARE/sbin:$DIR_ENTWARE/bin:\$PATH $DIR_ENTWARE/bin/bash $DIR_PROJECT_SHELL_SCRIPTS backup_auto >/dev/null 2>&1"
    if crontab -l 2>/dev/null | grep -q 'backup_auto'; then
        logmsg "${color_green}${ICO_MAP[INF]} Автоматические копии включены (по воскресеньям в 04:30).${style_plain}"
        confirm_options "Выключить автоматические копии" "n"
        if [[ $? == 0 ]]; then
            crontab -l 2>/dev/null | grep -v 'backup_auto' | crontab -
            logmsg "${color_yellow}Автоматические копии выключены.${style_plain}"
        fi
    else
        confirm_options "Включить автоматические копии базы раз в неделю (по воскресеньям в 04:30, хранится последних ${BACKUP_KEEP:-10})" "y"
        if [[ $? == 0 ]]; then
            { crontab -l 2>/dev/null | grep -v 'backup_auto'; echo "$line"; } | crontab -
            logmsg "${color_green}${ICO_MAP[INF]} Автоматические копии включены.${style_plain}"
            if ! pgrep -x crond >/dev/null 2>&1 && ! pgrep -x cron >/dev/null 2>&1; then
                logmsg "${color_yellow}${ICO_MAP[WAR]} Служба cron сейчас не запущена: без неё копии по расписанию делаться не будут.${style_plain}"
            fi
        fi
    fi
}
         
declare -A ext_map_unzip=( [gz]="gzip" [bz2]="bzip2" [xz]="xz" [zst]="zstd" [db]="cp" )
# Восстанавливает базу данных из выбранной резервной копии (программа распаковки выбирается по расширению файла).
restore(){
    is_files=("$DIR_PROJECT/backup/db"/*)
    is_files=( "${is_files[@]}" )
    if [[ ! -e "${is_files[0]}" ]]; then
        logmsg "Файлы резервных копий не найдены."
    else
        files=$(ls $DIR_PROJECT/backup/db/)
        menu_choice "$files" "" "Выберите копию для восстановления" "" "skip"
        selected_file="$schoice"
        fullpath="$DIR_PROJECT/backup/db/$selected_file"
        if [[ -f "$fullpath" ]]; then
            confirm_options "Вы уверены, что хотите восстановить данные из $selected_file... Текущие данные будут перезаписаны." "y"
            if [[ $? == 0 ]]; then
                logmsg "${color_yellow}${ICO_MAP[WAR]} Удаление старого файла базы данных: $DB${style_plain}"
                rm -rf $DB
                # По расширению файла (.gz, .zst, .xz, .bz2, .db) выбираем, чем его распаковывать.
                ext=${selected_file##*.}
                case ${ext=$?,,} in
                    db)
                        safe_call_command "${ext_map_unzip[$ext]}" "$fullpath" "$DB"
                        ;;
                    *)
                        if [[ -n ${ext_map_unzip[$ext]} ]]; then
                            safe_call_command "${ext_map_unzip[$ext]}" -dc "$fullpath" > "$DB"
                        else
                            logmsg "${color_red}${ICO_MAP[ERR]} Неподдерживаемое расширение файла резервной копии${style_plain}"
                            return 1
                        fi
                        ;;
                esac
                if [[ -f "$DB" ]]; then
                    logmsg "${color_green}${ICO_MAP[INF]} База данных успешно восстановлена из $selected_file. Расширение: $ext${style_plain}"
                    vacuum && integrity_check 
					confirm_restart
                    logmsg "${color_green}${ICO_MAP[INF]} Восстановление завершено: $DB. Проверьте работу панели.${style_plain}"
                else
                    logmsg "${color_red}${ICO_MAP[ERR]} Не удалось восстановить базу данных из $selected_file.${style_plain}"
                fi
            else
                logmsg "Восстановление отменено."
            fi
        else
            logmsg "${color_red}${ICO_MAP[ERR]} Файл резервной копии $selected_file не найден! Расширение: $ext${style_plain}"
        fi
    fi
}

# Меню резервных копий: создать / восстановить / удалить старые.
backup_management(){
    menu_choice menu_backup_management "$1"
    safe_call_function "$schoice"
}

# Меню управления настройками: резервные копии, geo-файлы, тест скорости, файл настроек, база данных, кэш, восстановление.
settings(){
    menu_choice menu_settings "$1"
    safe_call_function "$schoice"
}

# Выполняет VACUUM: сжимает и оптимизирует файл базы данных.
vacuum(){
    confirm_options "Выполнить VACUUM базы данных для оптимизации" "y"
    if [[ $? == 0 ]]; then
        logmsg "${ICO_MAP[WORK]} Выполняется VACUUM базы данных..."
        sqlite3 "$DB" "VACUUM;"
        if [ $? -eq 0 ]; then
            logmsg "${ICO_MAP[GOOD]} VACUUM базы данных успешно выполнен."
        else
            logmsg "${ICO_MAP[BAD]} Не удалось выполнить VACUUM базы данных."
        fi
    fi
}

# Проверяет целостность базы данных (PRAGMA integrity_check).
integrity_check(){
    confirm_options "Проверить целостность базы данных" "y"
    if [[ $? == 0 ]]; then
        logmsg "${ICO_MAP[WORK]} Проверка целостности базы данных..."
        result=$(sqlite3 "$DB" "PRAGMA integrity_check;")
        if [ "$result" == "ok" ]; then
            logmsg "${ICO_MAP[GOOD]} Проверка целостности базы данных пройдена."
        else
            logmsg "${ICO_MAP[BAD]} Проверка целостности базы данных не пройдена: $result"
        fi
    fi
}

# Меню работы с базой данных: выгрузка в json, загрузка из json, VACUUM, проверка целостности.
db_management(){
    menu_choice menu_db_management "$1"
    safe_call_function "$schoice"
}

# Удаляет кэш скрипта (вызывается при переустановке). Сообщения о json-файлах — справочные.
delete_config(){
    if [[ -d "$DIR_CACHE" ]]; then
        logmsg "${ICO_MAP[WORK]} ${color_green}Очистка кэша...${style_plain}"
        rm -rf "$DIR_CACHE" 2>/dev/null
		is_files=("$DIR_DB_IN_JSON/"/*)
		is_files=( "${is_files[@]}" )
		if [[ ! -e "${is_files[0]}" ]]; then
			logmsg "Файлы в $DIR_DB_IN_JSON/ удалены"
		else
            logmsg "Файлы не найдены"
        fi
    fi
}

# Пункт меню «Удалить все json-файлы»: после подтверждения вызывает delete_config.
delete_all_json(){
    confirm_options "Вы действительно хотите удалить все json-файлы"
    if [[ $? == 0 ]]; then
        delete_config
    fi
}

# Восстанавливает базу данных из json-файлов, ранее выгруженных функцией save_db_to_json.
# Файлы читаются построчно через jq и вставляются в таблицы командой INSERT OR REPLACE (в одной транзакции).
# Таблицы stats и changes пропускаются. Для работы нужно не менее 7 json-файлов.
restore_db_from_json() {
    local count
    count=$(ls -1 "$DIR_DB_IN_JSON"/*.json 2>/dev/null | wc -l)
    if [[ ! $count -ge 7 ]]; then
        logmsg "${ICO_MAP[BAD]} Недостаточно json-файлов конфигурации в $DIR_DB_IN_JSON/ (найдено: $count, требуется не менее 7). Восстановление прервано."
    else
    confirm_options "Восстановить конфигурацию из резервных json-файлов" "y"
        if [[ $? == 0 ]]; then
            # Перед записью в базу останавливаем панель.
            $0 stop
            # Вспомогательная функция: готовит значение для SQL (null → NULL, пусто → '', кавычки удваиваются).
            quote_or_null() {
                local v="$1"
                    if [ "$v" = "null" ]; then
                        printf "NULL"
                    elif [ -z "$v" ]; then
                        printf "''"
                    else
                        v="${v//\'/\'\'}"
                        printf "'%s'" "$v"
                    fi
            }
        [ ! -d "$DIR_DB_IN_JSON" ] && { logmsg "${ICO_MAP[BAD]} Каталог $DIR_DB_IN_JSON не найден"; return 1; }
        logmsg "${ICO_MAP[WORK]} Восстановление из $DIR_DB_IN_JSON..."
            ERR=0
            # Вся загрузка идёт одной транзакцией.
            sqlite3 "$DB" "BEGIN;" || ERR=1
            for f in "$DIR_DB_IN_JSON"/*.json; do
                [ -e "$f" ] || continue
                base=$(basename "$f")
                tbl="${base%.json}"
                case "$base" in
                    stats.json|changes.json)
                        logmsg "${ICO_MAP[WORK]} Пропуск $base (исключено)"
                        continue
                        ;;
                esac
        logmsg "${ICO_MAP[WORK]} Обработка таблицы $tbl..."
        mapfile -t cols < <(sqlite3 -separator '|' "$DB" "PRAGMA table_info(\"$tbl\");" | awk -F'|' '{print $2":"$3}')
                # Читаем json построчно: каждая строка — одна запись таблицы. Для каждой собираем и выполняем команду INSERT OR REPLACE.
                jq -c '.[]' "$f" | while read -r row; do
                    fields=()
                    values=()
                    for col in "${cols[@]}"; do
                        cname="${col%%:*}"
                        ctype=$(echo "${col#*:}" | tr '[:lower:]' '[:upper:]')
                        rawval=$(echo "$row" | jq -r --arg k "$cname" '.[$k] // empty')
                        if [ "$ctype" = "BLOB" ]; then
                            if [ "$rawval" = "null" ]; then
                                values+=(NULL)
                            elif [ -z "$rawval" ]; then
                                values+=("''")
                            elif [[ "$rawval" =~ ^\{.*\}$ || "$rawval" =~ ^\[.*\]$ ]]; then
                                 hex=$(printf '%s' "$rawval" | hexdump -v -e '/1 "%02x"')
                                values+=("X'$hex'")
                            elif echo "$rawval" | grep -qiE '^[0-9A-F]+$'; then
                                values+=("X'$rawval'")
                            else
                                hex=$(printf '%s' "$rawval" | hexdump -v -e '/1 "%02x"')
                                values+=("X'$hex'")
                            fi
                        else
                            values+=("$(quote_or_null "$rawval")")
                        fi
                        fields+=("\"$cname\"")
                    done
                    printf "INSERT OR REPLACE INTO \"%s\" (%s) VALUES (%s);\n" \
                        "$tbl" "$(IFS=,; echo "${fields[*]}")" "$(IFS=,; echo "${values[*]}")"
                done | sqlite3 "$DB" || ERR=1
            [ $ERR -eq 0 ] && logmsg "${ICO_MAP[GOOD]} $tbl восстановлена" || logmsg "${ICO_MAP[BAD]} Ошибка восстановления $tbl"
            done
            # Запускаем панель обратно, затем сжимаем базу и проверяем её.
            $0 start
            vacuum && integrity_check
        fi
    fi
}

# Выгружает каждую таблицу базы данных панели в отдельный json-файл (каталог /opt/etc/x-ui/db_in_json).
# Поля типа BLOB переводятся в текст (json остаётся json, остальное — в HEX). Таблицы stats и changes пропускаются.
save_db_to_json() {
    if [[ ! -f "$DB" ]]; then
        logmsg "${ICO_MAP[BAD]} Файл базы данных не найден: $DB"
        return 1
    fi
    mkdir -p "$DIR_DB_IN_JSON"
    local tables
    # Список таблиц базы данных.
    tables=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';")
    if [[ -z "$tables" ]]; then
        logmsg "${ICO_MAP[BAD]} В базе данных нет таблиц. Выполните: $SHELL_SHORT_NAME install или $NAME_APP migrate"
        return 1
    fi
    local exported=0 skipped=0
    for tbl in $tables; do
        case "$tbl" in
            stats|changes)
                logmsg "${ICO_MAP[WORK]} Пропуск $tbl (исключено)"
                skipped=$((skipped+1))
                continue
                ;;
        esac
        local pragma cols select_list=""
        pragma=$(sqlite3 -separator '|' "$DB" "PRAGMA table_info('$tbl');")
        while IFS='|' read -r _ name type _ _ _; do
            [[ -z "$name" ]] && continue
            local utype=$(echo "$type" | tr '[:lower:]' '[:upper:]')
            if [[ "$utype" == "BLOB" ]]; then
                select_list+=" , CASE
                    WHEN typeof(\"$name\") = 'null' THEN NULL
                    WHEN trim(\"$name\") = '' THEN ''
                    WHEN substr(trim(\"$name\"),1,1) = '{' OR substr(trim(\"$name\"),1,1) = '[' THEN \"$name\"
                    ELSE HEX(\"$name\") END AS \"$name\""
            else
                select_list+=" , \"$name\""
            fi
        done <<< "$pragma"
        select_list=${select_list# , }
        if [[ -z "$select_list" ]]; then
            logmsg "${ICO_MAP[BAD]} В таблице $tbl нет столбцов, пропуск"
            skipped=$((skipped+1))
            continue 
        fi
        local sql="SELECT $select_list FROM '$tbl';"
        local tmp_json
        tmp_json=$(sqlite3 -json "$DB" "$sql")
        if [[ -z "$tmp_json" || "$tmp_json" == "[\\n]\\n" ]]; then
            echo "[]" > "$DIR_DB_IN_JSON/$tbl.json"
        else
            tmpjq=$(mktemp)
            cat >"$tmpjq" <<'JQ'
def walk(f):
  . as $in
  | if type == "object" then
      reduce keys[] as $k ( {}; . + { ($k): ($in[$k] | walk(f)) } ) | f
    elif type == "array" then map( . | walk(f) ) | f
    else f
    end;
walk(if type == "string" and ((. | ltrimstr(" \t\n\r") | startswith("{") or startswith("["))) then (try fromjson catch .) else . end)
JQ
            if echo "$tmp_json" | jq -f "$tmpjq" > "$DIR_DB_IN_JSON/$tbl.json" 2>/dev/null; then
                rm -f "$tmpjq"
            else
                rm -f "$tmpjq"
                echo "$tmp_json" | jq '.' > "$DIR_DB_IN_JSON/$tbl.json"
            fi
        fi
        logmsg "${ICO_MAP[GOOD]} Экспортировано: $DIR_DB_IN_JSON/$tbl.json"
        exported=$((exported+1))
    done
    logmsg "${ICO_MAP[WORK]} Готово. Экспортировано: $exported, пропущено: $skipped"
}

# Выставляет права в каталоге проекта (/opt/etc/x-ui):
#   • исполняемые файлы (скрипт, панель, ядра Xray) — 755;
#   • каталоги с секретами (db — база, cert — сертификаты и ключи, backup — копии базы) закрываются от посторонних
#     (владелец остаётся прежним: 700 для каталогов, у файлов убираются права группы и остальных).
# Раньше на весь каталог ставилось 755, и приватный ключ с базой становились доступны для чтения всем.
permissions() {
    chmod 755 "$DIR_PROJECT" 2>/dev/null
    chmod 755 "$DIR_PROJECT_SHELL_SCRIPTS" "$DIR_PROJECT/$NAME_APP" 2>/dev/null
    chmod 755 "$DIR_PROJECT"/bin/xray-linux-* 2>/dev/null
    chmod -R go-rwx "$DIR_PROJECT/db" "$DIR_PROJECT/cert" "$DIR_PROJECT/backup" 2>/dev/null
}

# Приводит установку в порядок: переименовывает и переносит скрипт в /opt/etc/x-ui,
# создаёт команду x-ui (/opt/bin/x-ui) и восстанавливает ссылку автозапуска. Если файл переносился,
# запускает скрипт заново уже из нового места.
check_all_ruls(){
check_status
# Работаем, если панель установлена (или принудительно — параметр 1).
if [[ $? != 2 || $1 == 1 ]]; then
    # Скрипт запущен вручную (не из автозапуска).
    if [[ "$DIR_NOTREAL_CUR" != "$DIR_AUTO_START" ]]; then
        # Если файл называется иначе — переименовываем его в x-ui.sh.
        if [[ "$NAME_REAL_SHELL" != "$SHELL_FULL_NAME" ]]; then
            recall=1
            mv "$DIR_REAL_SHELL/$NAME_REAL_SHELL" "$DIR_REAL_SHELL/$SHELL_FULL_NAME"
        fi
        # Если скрипт лежит не в /opt/etc/x-ui — переносим его туда.
        if [[ "$DIR_REAL_SHELL" != "$DIR_PROJECT" ]]; then
            recall=1
            mkdir -p "$DIR_PROJECT"
            mv "$DIR_REAL_SHELL/$SHELL_FULL_NAME" "$DIR_PROJECT/$SHELL_FULL_NAME"
        fi
        # Создаём команду x-ui (ссылка в /opt/bin).
        if [[ ! -f $DIR_INSTALL_LNK ]]; then
            ln -s $DIR_PROJECT/$SHELL_FULL_NAME $DIR_INSTALL_LNK
            chmod u+x $DIR_INSTALL_LNK
        fi
        # Восстановление: если в каталоге repair лежит копия скрипта из автозапуска — возвращаем ссылку автозапуска.
        if [[ -d "$DIR_PROJECT/repair" && $(ls -A "$DIR_PROJECT/repair" 2>/dev/null) ]]; then
            repair=$(ls -t "$DIR_PROJECT/repair" | head -n 1)
            rm -f "$DIR_AUTO_START/$repair"
            ln -s "$DIR_PROJECT/$SHELL_FULL_NAME" "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME"
            rm -rf "$DIR_PROJECT/repair"
        bash $DIR_PROJECT/$SHELL_FULL_NAME "$COMMANDS_CALL"
        fi
    else
        # Запуск из автозапуска: на всякий случай сохраняем копию скрипта в каталог repair.
        if [[ "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME" != "$DIR_NOTREAL_CUR/$NAME_NOTREAL_SHELL" ]]; then
            if [[ ! -d "$DIR_PROJECT/repair" ]]; then
                mkdir -p "$DIR_PROJECT/repair"
            fi
            cp "$DIR_NOTREAL_CUR/$NAME_NOTREAL_SHELL" "$DIR_PROJECT/repair/"
        fi
        recall=1
    fi

    # Если файл переносился — запускаем скрипт заново уже из нового места.
    if [[ $recall -gt 0 ]]; then
        permissions
        bash $DIR_REAL_SHELL/$NAME_REAL_SHELL "$COMMANDS_CALL"
    fi
fi
}

# Узнаёт версию установленной панели (запускает xui -v) и запоминает её в кэше.
version_panel(){
    if [[ -f "$DIR_CACHE/$NAME_APP/version_$NAME_APP" && -z $no_cache_needed ]]; then
        source "$DIR_CACHE/$NAME_APP/version_$NAME_APP"
    else
        CURRENT_VERSION_ALL=$($DIR_PROJECT/$NAME_APP -v)
        CURRENT_VERSION_PANEL=$(echo "$CURRENT_VERSION_ALL")
        if [[ -z $no_cache_needed ]]; then
            if [[ ! -d "$DIR_CACHE/$NAME_APP/" ]]; then
                mkdir -p "$DIR_CACHE/$NAME_APP/"
            fi
            echo -e "CURRENT_VERSION_ALL=\"$CURRENT_VERSION_ALL\"" >> "$DIR_CACHE/$NAME_APP/version_$NAME_APP"
            echo -e "CURRENT_VERSION_PANEL=\"$CURRENT_VERSION_PANEL\"" >> "$DIR_CACHE/$NAME_APP/version_$NAME_APP"
        fi
    fi
}
# END PANEL COMMANDS ---------------------------------------------------------
# START MENU ------------------------------------------------------------
# Раздел «Меню»: тексты меню, главное меню и стартовый выбор режима установки.
# Прощается и завершает работу скрипта.
bye(){
    logmsg "${color_yellow}До свидания...${style_plain}"
    echo -e "" && exit 0
}

# Ждёт нажатия Enter и возвращает пользователя в главное меню.
# Параметр 1 — какую команду запустить вместо этого (используется после обновления скрипта).
before_show_main_menu() {
	echo -e "" && echo -n -e "${color_yellow}\u2190 Нажмите Enter для возврата в главное меню${style_plain}" && read temp
    if [[ -n $1 ]]; then
        exec $1
    else
        if check_status 2>/dev/null; [[ $? -eq 2 ]]; then
            bash "$DIR_NOTREAL_CUR/$NAME_NOTREAL_SHELL"
        else
            exec $SHELL_SHORT_NAME show_main_menu
        fi
    fi
}

# Проверка скорости интернета через iperf3 до сервера speedtest.serverius.net.
speedtest() {
	confirm_options "Запустить тест скорости для $SHELL_SHORT_NAME" "y"
	if [[ $? == 0 ]]; then
		logmsg "${ICO_MAP[WORK]} Запуск теста скорости..."
		safe_call_command iperf3 -Vc speedtest.serverius.net -p 5002
		logmsg "${ICO_MAP[INF]} Тест скорости завершён."
	fi
}

# Обновляет файлы geoip.dat и geosite.dat (списки адресов и сайтов для маршрутизации Xray) из выбранного набора.
update_geo() {

    menu_choice menu_update_geo_list "$1" "Выберите набор данных:"
    
    cd "$DIR_PROJECT/bin/" || return
	if [[ -n $schoice ]]; then
		stop
	fi
    case ${schoice=$?,,} in
    loyalsoldier)
        rm -f geoip.dat geosite.dat
        wget -N https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
        wget -N https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
        echo -e "${color_green}Наборы данных Loyalsoldier успешно обновлены!${style_plain}"
        ;;
    chocolate4u)
        rm -f geoip_IR.dat geosite_IR.dat
        wget -O geoip_IR.dat -N https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geoip.dat
        wget -O geosite_IR.dat -N https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geosite.dat
        echo -e "${color_green}Наборы данных chocolate4u успешно обновлены!${style_plain}"
        ;;
    runetfreedom)
        rm -f geoip_RU.dat geosite_RU.dat
        wget -O geoip_RU.dat -N https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat
        wget -O geosite_RU.dat -N https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat
        echo -e "${color_green}Наборы данных runetfreedom успешно обновлены!${style_plain}"
        ;;
    esac
	if [[ -n $schoice ]]; then
		confirm_restart
	fi
}

# Печатает одну строку отчёта диагностики и считает итоги. Параметры: 1 — уровень (ok, warn или fail), 2 — текст.
# Счётчики лежат в переменных DOC_OK, DOC_WARN, DOC_FAIL (их обнуляет doctor).
doctor_line() {
    case "$1" in
        ok)   echo -e "  ${color_green}✔${style_plain} $2"; DOC_OK=$((DOC_OK + 1)) ;;
        warn) echo -e "  ${color_yellow}⚠${style_plain} $2"; DOC_WARN=$((DOC_WARN + 1)) ;;
        *)    echo -e "  ${color_red}✘${style_plain} $2"; DOC_FAIL=$((DOC_FAIL + 1)) ;;
    esac
}

# Пункт меню «Диагностика» (команда x-ui doctor): проверяет установку и подсказывает, что исправить.
# Проверяется: Entware и процессор, место на диске, панель и автозапуск, порт, наш скрипт и команда x-ui, права на ключ и базу,
# HTTPS и срок сертификата, время и доступ к GitHub, нужные программы, ядро Xray, целостность базы, cron.
# Ничего не меняет. Код возврата 0, если ошибок (✘) нет, иначе 1: так диагностику можно использовать в скриптах.
doctor() {
    DOC_OK=0
    DOC_WARN=0
    DOC_FAIL=0
    echo -e "\n###############################################\n"
    echo -e "              ДИАГНОСТИКА $SHELL_SHORT_NAME"
    echo -e "\n###############################################\n"

    # --- система ---
    if [[ -x "$DIR_ENTWARE/bin/opkg" ]]; then
        doctor_line ok "Entware найден ($DIR_ENTWARE/bin/opkg)"
    else
        doctor_line fail "Entware не найден: скрипт рассчитан на Entware"
    fi
    local arch
    arch=$(check_architecture 1 >/dev/null 2>&1; echo "$ARCHITECTURE")
    if [[ -n "$arch" ]]; then
        doctor_line ok "Процессор: $arch (поддерживается)"
    else
        doctor_line fail "Процессор $(uname -m) не поддерживается панелью"
    fi
    local free_kb
    free_kb=$(df -k "$DIR_ENTWARE" 2>/dev/null | tail -n1 | awk '{print $(NF-2)}')
    if [[ "$free_kb" =~ ^[0-9]+$ ]]; then
        if (( free_kb < 20480 )); then
            doctor_line fail "Свободное место на $DIR_ENTWARE: $((free_kb / 1024)) МБ (меньше 20 МБ)"
        elif (( free_kb < 102400 )); then
            doctor_line warn "Свободное место на $DIR_ENTWARE: $((free_kb / 1024)) МБ (мало: обновление Xray и копии базы занимают место)"
        else
            doctor_line ok "Свободное место на $DIR_ENTWARE: $((free_kb / 1024)) МБ"
        fi
    fi

    # --- панель ---
    if [[ -x "$DIR_PROJECT/$NAME_APP" ]]; then
        doctor_line ok "Панель установлена, версия ${CURRENT_VERSION_ALL:-неизвестна}"
    else
        doctor_line fail "Файл панели не найден или не исполняемый: $DIR_PROJECT/$NAME_APP"
    fi
    if check_panel; then
        doctor_line ok "Панель запущена"
    else
        doctor_line fail "Панель не запущена (запустите: $SHELL_SHORT_NAME start)"
    fi
    if check_enabled; then
        doctor_line ok "Автозапуск включён"
    else
        doctor_line warn "Автозапуск выключен: после перезагрузки роутера панель не запустится"
    fi
    panel_settings_read
    if [[ -n "$PANEL_PORT" ]] && check_panel && command -v netstat >/dev/null 2>&1; then
        if netstat -ltn 2>/dev/null | grep -Eq "[:.]${PANEL_PORT}[[:space:]]"; then
            doctor_line ok "Порт панели $PANEL_PORT слушается"
        else
            doctor_line fail "Панель запущена, но порт $PANEL_PORT никто не слушает"
        fi
    fi

    # --- наш скрипт ---
    if [[ "$(head -n 1 "$DIR_PROJECT_SHELL_SCRIPTS" 2>/dev/null)" == "#!$DIR_ENTWARE/bin/bash" ]]; then
        doctor_line ok "Скрипт управления в порядке ($DIR_PROJECT_SHELL_SCRIPTS)"
    else
        doctor_line fail "В $DIR_PROJECT_SHELL_SCRIPTS другой скрипт (не наш): запустите команду установки из README, она восстановит файл"
    fi
    if [[ -e "$DIR_INSTALL_LNK" ]]; then
        doctor_line ok "Команда $SHELL_SHORT_NAME на месте ($DIR_INSTALL_LNK)"
    else
        doctor_line warn "Нет команды $DIR_INSTALL_LNK: запустите команду установки из README, она создаст ссылку"
    fi
    if [[ ":$PATH:" != *":$DIR_ENTWARE/bin:"* ]]; then
        doctor_line warn "В PATH нет $DIR_ENTWARE/bin: команду $SHELL_SHORT_NAME нужно запускать по полному пути или выполнить export PATH=$DIR_ENTWARE/sbin:$DIR_ENTWARE/bin:\$PATH"
    fi

    # --- права на секреты ---
    local f perm
    for f in "$PANEL_KEY" "$DB"; do
        [[ -n "$f" && -f "$f" ]] || continue
        perm=$(ls -l "$f" 2>/dev/null | cut -c5-10)
        if [[ "$perm" == "------" ]]; then
            doctor_line ok "Права на $f закрыты от посторонних"
        else
            doctor_line warn "Файл $f доступен посторонним: выполните chmod -R go-rwx $DIR_PROJECT/db $DIR_PROJECT/cert $DIR_PROJECT/backup"
        fi
    done

    # --- HTTPS ---
    if [[ -z "$PANEL_CERT" ]]; then
        doctor_line warn "HTTPS не включён: панель работает по HTTP (включить: пункт про SSL-сертификат в меню)"
    elif [[ ! -f "$PANEL_CERT" || ! -f "$PANEL_KEY" ]]; then
        doctor_line fail "Сертификат указан, но файлов нет: панель работает по HTTP (создайте сертификат или уберите настройку)"
    else
        local exp now days
        exp=$(cert_expiry_epoch "$PANEL_CERT")
        printf -v now '%(%s)T' -1
        if [[ -z "$exp" ]]; then
            doctor_line warn "Не удалось прочитать срок действия сертификата $PANEL_CERT"
        elif (( exp <= now )); then
            doctor_line fail "SSL-сертификат истёк: создайте новый"
        elif (( (exp - now) / 86400 <= 30 )); then
            doctor_line warn "SSL-сертификат истекает через $(( (exp - now) / 86400 )) дн.: пора обновить"
        else
            doctor_line ok "SSL-сертификат действителен ещё $(( (exp - now) / 86400 )) дн."
        fi
    fi

    # --- время и сеть ---
    local year
    printf -v year '%(%Y)T' -1
    if (( year < 2025 )); then
        doctor_line fail "Время на роутере неверно (год $year): HTTPS и сертификаты работать не будут"
    fi
    local head_out code
    head_out=$(curl -4 -sI --max-time 8 https://github.com 2>/dev/null)
    if [[ -n "$head_out" ]]; then
        doctor_line ok "github.com доступен"
        # Сравниваем время роутера со временем сервера (заголовок Date: Wed, 05 Nov 2026 12:00:00 GMT)
        local dline dow dd mon yy tm mm h mi s now2 skew months=" Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec" pre
        dline=$(echo "$head_out" | grep -i '^date:' | head -n1 | tr -d '\r')
        read -r _ _ dd mon yy tm _ <<< "$dline"
        if [[ -n "$mon" && "$months" == *" $mon"* ]]; then
            pre="${months%% $mon*}"
            mm=$(( $(wc -w <<< "$pre") + 1 ))
            IFS=: read -r h mi s <<< "$tm"
            utc_epoch "$yy" "$mm" "$dd" "$h" "$mi" "$s"
            printf -v now2 '%(%s)T' -1
            skew=$(( now2 - UTC_EPOCH ))
            (( skew < 0 )) && skew=$(( -skew ))
            if (( skew > 300 )); then
                doctor_line warn "Время роутера расходится с реальным на $(( skew / 60 )) мин.: проверьте синхронизацию времени"
            else
                doctor_line ok "Время роутера совпадает с реальным"
            fi
        fi
    else
        doctor_line fail "github.com недоступен: не будут работать установка, обновления и проверка версий"
    fi
    code=$(curl -4 -s -o /dev/null -w '%{http_code}' --max-time 8 https://raw.githubusercontent.com 2>/dev/null)
    if [[ -n "$code" && "$code" != "000" ]]; then
        doctor_line ok "raw.githubusercontent.com доступен (скрипт обновляется отсюда)"
    else
        doctor_line warn "raw.githubusercontent.com недоступен: обновление самого скрипта не заработает"
    fi

    # --- программы ---
    local c
    for c in curl openssl sqlite3 tar pgrep; do
        if command -v "$c" >/dev/null 2>&1; then
            :
        else
            doctor_line fail "Нет программы $c (установка: opkg install $c)"
        fi
    done

    # --- ядро и база ---
    local xv
    xv=$(xray_version)
    if [[ -n "$xv" ]]; then
        doctor_line ok "Ядро Xray запускается, версия $xv"
    else
        doctor_line fail "Ядро Xray не найдено или не запускается: $DIR_PROJECT/bin"
    fi
    if command -v sqlite3 >/dev/null 2>&1 && [[ -f "$DB" ]]; then
        if [[ "$(sqlite3 -readonly "$DB" 'PRAGMA quick_check;' 2>/dev/null | head -n1)" == "ok" ]]; then
            doctor_line ok "База данных цела"
        else
            doctor_line fail "База данных повреждена: восстановите её из резервной копии (меню → Управление настройками)"
        fi
    fi

    # --- cron (нужен для продления сертификата и резервных копий по расписанию) ---
    local cron_jobs=0
    if command -v crontab >/dev/null 2>&1; then
        crontab -l 2>/dev/null | grep -Eq 'acme\.sh --cron|backup_auto' && cron_jobs=1
    fi
    if [[ $cron_jobs -eq 1 ]]; then
        if pgrep -x crond >/dev/null 2>&1 || pgrep -x cron >/dev/null 2>&1; then
            doctor_line ok "Задания cron есть, служба cron запущена"
        else
            doctor_line warn "Задания cron есть, но служба cron не запущена: продление сертификата и копии по расписанию не сработают"
        fi
    elif ! command -v crontab >/dev/null 2>&1; then
        doctor_line warn "Нет планировщика cron: автопродление сертификата и копии по расписанию недоступны (установка: opkg install cron)"
    fi

    echo -e "\n  Итого: ${color_green}✔ $DOC_OK${style_plain}   ${color_yellow}⚠ $DOC_WARN${style_plain}   ${color_red}✘ $DOC_FAIL${style_plain}\n"
    if [[ $DOC_FAIL -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Пункт меню «Доступ из интернета» — мастер, который открывает панель для доступа из интернета или возвращает доступ только из локальной сети.
# По умолчанию панель слушает только адрес роутера в локальной сети (так безопаснее всего). Мастер меняет адрес прослушивания
# (0.0.0.0 — все адреса) и подсказывает, что ещё нужно сделать: открыть порт в межсетевом экране роутера, включить HTTPS, задать сложный пароль.
# Межсетевым экраном Keenetic скрипт управлять не может: порт нужно открыть самому в настройках роутера.
remote_access() {
    local bin="$DIR_PROJECT/$NAME_APP" lan scheme="http" https=0 open=0
    if [[ ! -x "$bin" ]]; then
        logmsg "${color_red}${ICO_MAP[ERR]} Панель не установлена.${style_plain}"
        return 1
    fi
    if ! panel_settings_read; then
        logmsg "${color_red}${ICO_MAP[ERR]} Не удалось прочитать настройки панели (нужны база данных и программа sqlite3).${style_plain}"
        return 1
    fi
    lan=$(lan_ip)
    [[ -z "$PANEL_LISTEN" || "$PANEL_LISTEN" == "0.0.0.0" ]] && open=1
    if [[ -n "$PANEL_CERT" && -n "$PANEL_KEY" && -f "$PANEL_CERT" && -f "$PANEL_KEY" ]]; then
        https=1
        scheme="https"
    fi
    echo -e "\n###############################################\n"
    echo -e "              ДОСТУП ИЗ ИНТЕРНЕТА"
    echo -e "\n###############################################\n"
    if [[ $open -eq 1 ]]; then
        logmsg "${color_yellow}${ICO_MAP[WAR]} Сейчас панель открыта: она слушает все адреса (порт $PANEL_PORT).${style_plain}"
        confirm_options "Вернуть доступ только из локальной сети (${lan:-IP роутера})" "y"
        if [[ $? != 0 ]]; then
            return 0
        fi
        if [[ -z "$lan" ]]; then
            logmsg "${color_red}${ICO_MAP[ERR]} Не удалось определить IP роутера. Задайте адрес прослушивания через «Изменить настройки панели».${style_plain}"
            return 1
        fi
        "$bin" setting -listenIP "$lan" >/dev/null 2>&1
        confirm_restart
        logmsg "${color_green}${ICO_MAP[INF]} Панель снова доступна только из локальной сети: ${scheme}://${lan}:${PANEL_PORT}${PANEL_PATH}${style_plain}"
        return 0
    fi

    logmsg "${color_green}Сейчас панель доступна только из локальной сети: адрес ${PANEL_LISTEN}, порт $PANEL_PORT.${style_plain}"
    echo -e "Открывать панель в интернет стоит, только если это действительно нужно: к ней смогут подбирать пароль все желающие."
    echo -e "Что желательно сделать до открытия:"
    echo -e "  • включить HTTPS (лучше сертификат для своего домена, пункт «Получить SSL-сертификат»);"
    echo -e "  • задать сложные логин и пароль и не оставлять стандартный путь панели;"
    echo -e "  • открыть TCP-порт $PANEL_PORT в межсетевом экране роутера (скрипт этого сделать не может)."
    if [[ $https -eq 0 ]]; then
        logmsg "${color_red}${ICO_MAP[WAR]} HTTPS не включён: логин и пароль будут передаваться по интернету открытым текстом.${style_plain}"
        confirm_options "Всё равно открыть панель без HTTPS" "n" "" "$color_red"
        if [[ $? != 0 ]]; then
            logmsg "${color_yellow}Отменено. Сначала включите HTTPS (пункты про SSL-сертификат в меню).${style_plain}"
            return 0
        fi
    fi
    confirm_options "Открыть панель для доступа из интернета (слушать на всех адресах)" "n" "" "$color_red"
    if [[ $? != 0 ]]; then
        return 0
    fi
    "$bin" setting -listenIP 0.0.0.0 >/dev/null 2>&1
    panel_settings_read
    if [[ -n "$PANEL_LISTEN" && "$PANEL_LISTEN" != "0.0.0.0" ]]; then
        logmsg "${color_red}${ICO_MAP[ERR]} Панель не приняла новый адрес прослушивания.${style_plain}"
        return 1
    fi
    confirm_restart
    local ext
    ext=$(curl -4 -s --max-time 5 https://api.ipify.org 2>/dev/null)
    logmsg "${color_green}${ICO_MAP[INF]} Панель открыта для доступа из интернета.${style_plain}"
    echo -e "Адрес из интернета: ${scheme}://${ext:-<внешний IP или домен>}:${PANEL_PORT}${PANEL_PATH}"
    echo -e "Не забудьте открыть TCP-порт ${PANEL_PORT} в межсетевом экране роутера (Сетевые правила → Межсетевой экран)."
    echo -e "Вернуть доступ только из локальной сети можно тем же пунктом меню."
}

# Восстановление установки: права на файлы, перенос скрипта, миграция базы, VACUUM и проверка целостности.
repair(){
    confirm_options "Вы действительно хотите восстановить установку $SHELL_SHORT_NAME" "n"
    if [[ $? == 0 ]]; then
		logmsg "${ICO_MAP[WORK]} Восстановление установки $SHELL_SHORT_NAME..."
        permissions && check_all_ruls 1 && migration && vacuum && integrity_check
		logmsg "${ICO_MAP[INF]} Восстановление завершено."
		confirm_restart
    fi
}

# Тексты меню. Формат пункта: «ключ::Текст», [br] — разделительная линия. Главное меню собирается из menu_exit + menu_install (панели нет) или menu_exit + menu_extra (панель есть).
menu_exit="exit::${color_magenta}Выход${style_plain}
[br]
"
# Меню, когда панель ещё не установлена.
menu_install="
install::Установить $SHELL_SHORT_NAME ${color_green}(последняя версия)${style_plain}
custom::Установить свою версию $SHELL_SHORT_NAME ${color_yellow}(не рекомендуется)${style_plain}
"
# Меню управления установленной панелью.
menu_extra="update::Проверка обновлений
uninstall::Удалить панель $SHELL_SHORT_NAME
install_custom::Установить свою версию $NAME_APP/скрипта  ${color_yellow}(не рекомендуется)${style_plain}
[br]
settings::Управление настройками
log::Просмотр журнала $SHELL_SHORT_NAME
[br]
reset_admin::Сбросить учётные данные администратора
set_admin::Задать учётные данные администратора
reset_panel::Сбросить настройки панели
set_panel::Изменить настройки панели
view_panel::Показать настройки панели
[br]
ssl::Создать самоподписанный SSL-сертификат
ssl_domain::Получить SSL-сертификат для своего домена (Let's Encrypt)
ssl_remove::Удалить SSL-сертификат (вернуться к HTTP)
[br]
start::Запустить $SHELL_SHORT_NAME
stop::Остановить $SHELL_SHORT_NAME
restart::Перезапустить $SHELL_SHORT_NAME
status::Проверить состояние $SHELL_SHORT_NAME
[br]
enable::Включить автозапуск $SHELL_SHORT_NAME
disable::Отключить автозапуск $SHELL_SHORT_NAME
[br]
doctor::Диагностика (проверка установки)
remote_access::Доступ из интернета (мастер)
"
# Подменю «своя версия».
menu_install_custom="
show_main_menu::${color_magenta}Главное меню${style_plain}
[br]
install_custom_panel::Установить свою версию панели $NAME_APP  ${color_yellow}(не рекомендуется)${style_plain}
install_custom_script::Установить свою версию скрипта  ${color_yellow}(не рекомендуется)${style_plain}
"
# Подменю обновления.
menu_update="
show_main_menu::${color_magenta}Главное меню${style_plain}
[br]
update_all::Обновить всё
update_script::Обновить только скрипт
update_panel::Обновить только панель
update_xray::Обновить только XRay
update_xray_custom::Установить свою версию XRay
rollback_xray::Откатить XRay (вернуть прежнюю версию)
"
# Подменю настроек.
menu_settings="
show_main_menu::${color_magenta}Главное меню${style_plain}
[br]
backup_management::Управление резервными копиями
update_geo::Обновить файлы geo
speedtest::Проверить скорость интернет-соединения
edit_settings::Редактировать файл настроек вручную
db_management::Управление базой данных
clear_all_cache::Очистить весь кэш
repair::Восстановить установку $SHELL_SHORT_NAME
"
# Подменю работы с базой данных.
menu_db_management="
show_main_menu::${color_magenta}Главное меню${style_plain}
[br]
save_db_to_json::Сохранить базу данных в json-файлы
restore_db_from_json::Восстановить базу данных из json-файлов ${color_red}(осторожно!)${style_plain}
delete_all_json::Удалить все json-файлы
[br]
vacuum::Выполнить VACUUM базы данных
integrity_check::Проверить целостность базы данных
"
# Подменю резервных копий.
menu_backup_management="
show_main_menu::${color_magenta}Главное меню${style_plain}
[br]
backup::Создать резервную копию базы данных панели
restore::Восстановить базу данных панели из копии
delete_old_backups::Удалить старые резервные копии
backup_cron::Автоматические копии по расписанию (вкл/выкл)
"
# Способы сжатия резервной копии (ключ = имя программы сжатия).
menu_archive="
zstd::ZSTD: максимальное сжатие, быстро ${color_green}(рекомендуется)${style_plain}
gzip::GZIP: слабое сжатие, быстро
bzip2::BZIP2: сильное сжатие, но медленнее
xz::XZ: максимальное сжатие, занимает больше времени
cp::CP: без сжатия, очень быстро
"
# Типы ключей для самоподписанного сертификата.
menu_ssl="
rsa_4096::RSA_4096 ${color_green}(рекомендуется, принимают все браузеры)${style_plain}
rsa_2048::RSA_2048
ecdsa_prime256v1::ECDSA_prime256v1
ecdsa_secp384r1::ECDSA_secp384r1
ed25519::Ed25519 ${color_yellow}(многие браузеры не принимают)${style_plain}
"
# Наборы geo-файлов для обновления.
menu_update_geo_list="
loyalsoldier::Loyalsoldier: наборы данных (geoip.dat, geosite.dat)
chocolate4u::chocolate4u: наборы данных (geoip_IR.dat, geosite_IR.dat)
runetfreedom::runetfreedom: наборы данных (geoip_RU.dat, geosite_RU.dat)
"
# Стартовый выбор режима установки (показывается, когда панели ещё нет).
menu_start="
auto_install::Автоматическая установка ${color_green}(последняя версия, HTTPS, случайный пароль, автозапуск)${style_plain}
manual::Самостоятельная настройка (каждый пункт настраиваете сами)
"
# Отпечаток текстов всех меню. Если меню изменилось (даже при той же версии скрипта), старый кэш меню сбрасывается сам.
MENU_HASH=$(printf '%s' "$menu_exit$menu_install$menu_extra$menu_install_custom$menu_update$menu_settings$menu_db_management$menu_backup_management$menu_archive$menu_ssl$menu_update_geo_list$menu_start" | { cksum 2>/dev/null || md5sum 2>/dev/null; } | cut -d' ' -f1)
MENU_HASH="${MENU_HASH:-$CURRENT_VERSION_SCRIPT}"
if check_status 2>/dev/null; [[ ! $? -eq 2 ]]; then
    version_panel
fi

# Последняя версия самого скрипта: берётся из строки CURRENT_VERSION_SCRIPT в x-ui.sh в ветке main репозитория SCRIPT_REPO.
# Печатает номер (например, 1.0.5) или ничего, если проверить не удалось.
script_last_version() {
    curl -4 -fsSL --max-time 6 "$SCRIPT_RAW/main/$SHELL_FULL_NAME" 2>/dev/null | grep -m1 '^CURRENT_VERSION_SCRIPT=' | cut -d'"' -f2
}

# Последняя версия панели 3x-ui на GitHub (MHSanaei/3x-ui), например v3.12.0.
panel_last_version() {
    github_latest_tag MHSanaei/3x-ui 6
}

# Сравнивает два номера версии по числам (1.0.10 больше 1.0.9). Печатает 1, если первая версия новее, -1, если старее, 0, если равны.
# Буквы и приставка v игнорируются: берутся только цифры каждой части номера.
version_cmp() {
    local a b i x y n
    IFS=. read -ra a <<< "${1#v}"
    IFS=. read -ra b <<< "${2#v}"
    n=${#a[@]}
    (( ${#b[@]} > n )) && n=${#b[@]}
    for ((i = 0; i < n; i++)); do
        x=${a[i]//[^0-9]/}
        y=${b[i]//[^0-9]/}
        x=${x:-0}
        y=${y:-0}
        if ((10#$x > 10#$y)); then echo 1; return; fi
        if ((10#$x < 10#$y)); then echo -1; return; fi
    done
    echo 0
}

# Цветная точка статуса версии. Параметры: 1 — установленная версия, 2 — последняя версия на GitHub.
#   зелёная ● — стоит самая свежая версия;
#   жёлтая  ● — доступно обновление;
#   красная ● — проверить не удалось (нет интернета, GitHub не отвечает или версия не определена).
version_dot() {
    local cur="$1" last="$2"
    if [[ -z "$cur" || -z "$last" ]]; then
        echo -e "${color_red}●${style_plain}"
    elif [[ "$(version_cmp "$cur" "$last")" == "-1" ]]; then
        echo -e "${color_yellow}●${style_plain}"
    else
        echo -e "${color_green}●${style_plain}"
    fi
}

# Узнаёт последние версии скрипта, панели и Xray на GitHub и сохраняет их в кэш (LATEST_SCRIPT, LATEST_PANEL, LATEST_XRAY).
# Три запроса идут одновременно, у каждого ограничено время ожидания, поэтому меню не зависает даже без интернета.
# Ответ проверяется на вид «1.2.3» или «v1.2.3»: всё остальное (страница с ошибкой и т. п.) считается неудачей. Пустое значение = «не удалось проверить».
refresh_latest_versions() {
    local tmp="$DIR_TMP/latest.$$" p1 p2 p3 v
    mkdir -p "$tmp" "$DIR_CACHE"
    ( script_last_version > "$tmp/script" 2>/dev/null ) & p1=$!
    ( panel_last_version  > "$tmp/panel"  2>/dev/null ) & p2=$!
    ( xray_last_version   > "$tmp/xray"   2>/dev/null ) & p3=$!
    wait $p1 $p2 $p3 2>/dev/null
    for v in script panel xray; do
        local val
        val=$(head -n1 "$tmp/$v" 2>/dev/null | tr -cd 'A-Za-z0-9._+-')
        [[ "$val" =~ ^v?[0-9]+(\.[0-9]+)+$ ]] || val=""
        case $v in
            script) LATEST_SCRIPT="$val" ;;
            panel)  LATEST_PANEL="$val" ;;
            xray)   LATEST_XRAY="$val" ;;
        esac
    done
    LATEST_CHECK_TIME=$(date +%s)
    printf 'LATEST_CHECK_TIME="%s"\nLATEST_SCRIPT="%s"\nLATEST_PANEL="%s"\nLATEST_XRAY="%s"\n' \
        "$LATEST_CHECK_TIME" "$LATEST_SCRIPT" "$LATEST_PANEL" "$LATEST_XRAY" > "$DIR_CACHE/latest_versions"
    rm -rf "$tmp"
}

# Подготавливает LATEST_SCRIPT, LATEST_PANEL и LATEST_XRAY для точек статуса в шапке меню.
# Берёт значения из кэша; если кэша нет или он устарел, обращается к GitHub (refresh_latest_versions).
# Срок годности кэша: 30 минут, если все три версии проверены, и 1 минута, если что-то не удалось (чтобы быстро перепроверить).
load_latest_versions() {
    local f="$DIR_CACHE/latest_versions" ttl=1800 age
    LATEST_CHECK_TIME=0
    LATEST_SCRIPT=""
    LATEST_PANEL=""
    LATEST_XRAY=""
    [[ -f "$f" ]] && source "$f"
    if [[ -z "$LATEST_SCRIPT" || -z "$LATEST_PANEL" || -z "$LATEST_XRAY" ]]; then
        ttl=60
    fi
    age=$(( $(date +%s) - ${LATEST_CHECK_TIME:-0} ))
    if (( age < 0 || age >= ttl )); then
        echo -ne "Проверка версий...\r"
        refresh_latest_versions
        echo -ne "\033[K"
    fi
}
# Экранирует строку для JSON и печатает её в кавычках (обратная косая черта, кавычки, переводы строки, табуляция).
json_str() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    printf '"%s"' "$s"
}

# Печатает состояние панели в формате JSON (команда x-ui status --json): версии скрипта, панели и Xray, работает ли панель,
# включён ли автозапуск, адрес и порт, HTTPS и сколько дней осталось у сертификата (null, если сертификата нет или срок неизвестен).
# Пригодно для мониторинга и скриптов. Ничего, кроме JSON, не печатает. Код возврата 0, если панель работает.
status_json() {
    local running=false enabled=false https=false days=null port=null exp now
    check_panel && running=true
    check_enabled && enabled=true
    if panel_settings_read; then
        port="$PANEL_PORT"
        if [[ -n "$PANEL_CERT" && -n "$PANEL_KEY" && -f "$PANEL_CERT" && -f "$PANEL_KEY" ]]; then
            https=true
            exp=$(cert_expiry_epoch "$PANEL_CERT")
            if [[ -n "$exp" ]]; then
                printf -v now '%(%s)T' -1
                days=$(( (exp - now) / 86400 ))
            fi
        fi
    fi
    printf '{\n'
    printf '  "script": %s,\n' "$(json_str "$CURRENT_VERSION_SCRIPT")"
    printf '  "panel": %s,\n' "$(json_str "$CURRENT_VERSION_ALL")"
    printf '  "xray": %s,\n' "$(json_str "$(xray_version)")"
    printf '  "running": %s,\n' "$running"
    printf '  "autostart": %s,\n' "$enabled"
    printf '  "listen": %s,\n' "$(json_str "$PANEL_LISTEN")"
    printf '  "port": %s,\n' "$port"
    printf '  "path": %s,\n' "$(json_str "$PANEL_PATH")"
    printf '  "https": %s,\n' "$https"
    printf '  "cert_days_left": %s\n' "$days"
    printf '}\n'
    [[ "$running" == true ]]
}

# Печатает одну строку отчёта о версии и возвращает код: 0 — стоит последняя версия, 10 — есть обновление, 2 — проверить не удалось.
# Параметры: 1 — название, 2 — установленная версия, 3 — последняя версия на GitHub.
update_row() {
    local label="$1" cur="$2" last="$3"
    if [[ -z "$cur" || -z "$last" ]]; then
        echo -e "$label ${cur:-?}: проверить не удалось $(status_dot red)"
        return 2
    elif [[ "$(version_cmp "$cur" "$last")" == "-1" ]]; then
        echo -e "$label $cur: доступна ${last#v} $(status_dot yellow)"
        return 10
    fi
    echo -e "$label $cur: последняя версия $(status_dot green)"
    return 0
}

# Проверка наличия новых версий скрипта, панели и Xray (команда x-ui update --check). Всегда спрашивает GitHub заново (кэш не используется)
# и обновляет кэш для точек в шапке меню. Ничего не устанавливает.
# Код возврата: 0 — всё последнее, 10 — есть обновления, 2 — что-то проверить не удалось (удобно для cron и мониторинга).
check_updates() {
    local rc any_update=0 any_fail=0
    refresh_latest_versions
    update_row "Скрипт:" "$CURRENT_VERSION_SCRIPT" "$LATEST_SCRIPT"; rc=$?
    [[ $rc -eq 10 ]] && any_update=1
    [[ $rc -eq 2 ]] && any_fail=1
    update_row "Панель: " "$CURRENT_VERSION_ALL" "$LATEST_PANEL"; rc=$?
    [[ $rc -eq 10 ]] && any_update=1
    [[ $rc -eq 2 ]] && any_fail=1
    update_row "XRay:   " "$(xray_version)" "$LATEST_XRAY"; rc=$?
    [[ $rc -eq 10 ]] && any_update=1
    [[ $rc -eq 2 ]] && any_fail=1
    [[ $any_fail -eq 1 ]] && return 2
    [[ $any_update -eq 1 ]] && return 10
    return 0
}


# Очищает экран и печатает логотип.
show_logo() {
    echo -e "${style_new_line}${color_red}
 _____ __   __        _    _   _ 
|____ |\ \ / /       | |  | | (_)
    / / \ V /  ____  | |  | |  _ 
    \ \ / _ \ |____| | |  | | | |
____/ // / \ \       | |__| | | |
\____/ \/   \/        \____/  |_|
${style_plain}
"
}

# Стартовое меню при первом запуске (когда панель ещё не установлена):
#   1 — автоматическая установка (auto_install),
#   2 — самостоятельная настройка (обычное меню, где каждый шаг делается вручную).
start_choice() {
    show_logo
    echo -e "${color_yellow}Скрипт ${SHELL_SHORT_NAME^^}:     ${color_white}${CURRENT_VERSION_SCRIPT}${style_plain}"
    echo -e "\nПанель ${SHELL_SHORT_NAME} ещё не установлена. Выберите режим установки:"
    while true; do
        menu_choice menu_start "" "Выберите режим установки"
        case "$schoice" in
            auto_install)
                auto_install
                break
                ;;
            manual)
                show_main_menu
                break
                ;;
            *)
                logmsg "${color_red}${ICO_MAP[ERR]} Неверный выбор: введите 1 или 2.${style_plain}"
                ;;
        esac
    done
}

# Главное меню. Если панели нет — предлагает установить, если есть — показывает состояние и все пункты управления.
# Можно вызвать с командой, например show_main_menu restart: тогда меню не показывается, а команда выполняется сразу.
show_main_menu() {
schoice=""
# Если передана команда (x-ui restart) — меню не показываем, сразу выполняем её.
if [[ $# -gt 0 ]]; then
	call=$1
else
    # Панель только что установлена (есть метка new): предлагаем сразу запустить её и включить автозапуск.
    if [[ -d "$DIR_PROJECT/new" ]]; then
        check_all_ruls && dos2unix "$DIR_REAL_SHELL/$NAME_REAL_SHELL"
        confirm_options "Запустить $SHELL_SHORT_NAME и включить автозапуск" "y"
        if [[ $? == 0 ]]; then
            start && enable
        fi
        rm -rf "$DIR_PROJECT/new"
    fi
	commands_arg=$2
show_logo
    # Если панель установлена, заранее узнаём последние версии (из кэша или с GitHub) для цветных точек справа от версий
    local dot_script="" dot_panel=""
    if [[ -f $DIR_PROJECT/$NAME_APP && "$CHECK_UPDATES" == true ]]; then
        load_latest_versions
        dot_script=" $(version_dot "$CURRENT_VERSION_SCRIPT" "$LATEST_SCRIPT")"
        dot_panel=" $(version_dot "$CURRENT_VERSION_ALL" "$LATEST_PANEL")"
    fi
    echo -e "${color_yellow}Скрипт ${SHELL_SHORT_NAME^^}:     ${color_white}${CURRENT_VERSION_SCRIPT}${style_plain}${dot_script}"
	# Собираем меню: «Выход» + пункты установки (если панели нет) или пункты управления (если панель есть).
	show_main_menu=$menu_exit
    if [[ -f $DIR_PROJECT/$NAME_APP ]]; then
        echo -e "Панель ${SHELL_SHORT_NAME^^}:     $CURRENT_VERSION_ALL${dot_panel}" && show_xray_version && show_panel_info && show_time_warning && show_main_menu+=$menu_extra && echo -e "" && show_status && echo -e ""
	else
        show_main_menu+=$menu_install
    fi
    menu_choice show_main_menu "$schoice"
    call=$schoice
fi
logmsg "Choice: $call" nolog
	# Что делать по выбранному ключу (ключ приводится к нижнему регистру).
	case ${call,,} in
        exit)
            bye
        ;;
        install)
            check_uninstall && safe_call_function "$call" $NAME_APP
        ;;
        auto|auto_install)
            safe_call_function auto_install
        ;;
        custom)
            check_uninstall && safe_call_function "$call" $NAME_APP "$commands_arg"
        ;;		
        *)
            if [[ -n "$call" ]]; then
                check_install && safe_call_function "$call" "$commands_arg"
            fi
        ;;
	esac
}
# END MENU ------------------------------------------------------------
logmsg "Script $SHELL_FULL_NAME was called by $USER" nolog
logmsg "Command line arguments: $([[ $# -eq 0 ]] && echo "$SHELL_SHORT_NAME")" nolog
logmsg "DIR EXECUTE: $DIR_NOTREAL_CUR/$NAME_NOTREAL_SHELL" nolog
# Точка входа. Скрипт может быть запущен двумя способами:
#   1) системой при загрузке роутера — через ссылку /opt/etc/init.d/S99x-ui (тогда выполняются только start/stop/restart/status);
#   2) пользователем — с командой (x-ui restart) или без неё (меню).
# AUTO_START ------------------------------------------------------------
if [[ "$DIR_NOTREAL_CUR" == "$DIR_AUTO_START" ]]; then
    logmsg "Auto start script initialized" nolog
    PATH=/opt/sbin:/opt/bin:/opt/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    ACTION=$1
    CALLER=$2
    logmsg "Auto start script: $ACTION by $CALLER" nolog
        case $ACTION in
            start)
                $ACTION
                ;;
            stop|kill)
                status && stop
                ;;
            restart)
                $ACTION
                ;;
            check|status)
                status
                ;;
            *)
                echo -e "  Команды: ${color_green}start${style_plain} | ${color_red}stop${style_plain} | ${color_yellow}restart${style_plain} | status"
                ;;
        esac
    logmsg "Auto start script ended" nolog
    exit 1
else
    # Обычный запуск пользователем. Нужны права root.
    [[ $EUID -ne 0 ]] && logmsg "${color_red}Критическая ошибка: ${style_plain} Запустите скрипт с правами root \n " && exit 1
    if [[ $# -gt 0 ]]; then
    # Скрипт вызван с командой, например: x-ui restart, x-ui ssl_domain, x-ui auto_install.
    COMMANDS_CALL=$1 && commands_arg=$2
        # Код возврата команды сохраняем и отдаём как код выхода скрипта (нужно для cron и мониторинга: x-ui update --check, x-ui doctor)
        if check_status 2>/dev/null; [[ $? -eq 2 ]]; then
            show_main_menu "$COMMANDS_CALL" "$commands_arg"
            CLI_RC=$?
        elif check_status 2>/dev/null; [[ ! $? -eq 2 ]]; then
            check_install && safe_call_function "$@"
            CLI_RC=$?
        else
            logmsg "${color_red}${ICO_MAP[ERR]} Сначала установите панель! ${style_plain}" && bye
        fi
    else
        if check_status 2>/dev/null; [[ $? -eq 2 ]]; then
            # Панели ещё нет: сначала выбор — автоматическая установка или самостоятельная настройка.
            start_choice
        else
            show_main_menu
        fi
    fi
    check_show_main_menu
    exit "${CLI_RC:-0}"
fi
# AUTO_END ------------------------------------------------------------