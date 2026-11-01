#!/bin/sh
# install-3xui-keenetic.sh: установка 3x-ui на Keenetic (Entware, aarch64) одной командой.
#
# Запуск (на роутере, по SSH в Entware, от root):
#   curl -fsSL https://raw.githubusercontent.com/byDGer/3xui-keenetic-aarch64/main/install-3xui-keenetic.sh | sh
# Нужны curl и ca-certificates:  opkg update && opkg install curl ca-certificates
#
# Что делает этот файл: проверяет окружение, ставит минимальные пакеты, скачивает управляющий
# скрипт x-ui.sh из этого репозитория и запускает его. Дальше работает x-ui.sh: он показывает выбор
#   1) Автоматическая установка (последняя версия панели с MHSanaei/3x-ui, самоподписанный сертификат
#      и HTTPS, случайные логин и пароль, автозапуск);
#   2) Самостоятельная настройка (обычное меню, всё настраиваете вы).
#
# Чтобы пропустить выбор и сразу выполнить автоматическую установку, добавьте аргумент auto:
#   curl -fsSL https://raw.githubusercontent.com/byDGer/3xui-keenetic-aarch64/main/install-3xui-keenetic.sh | sh -s -- auto
# Если терминала нет (например, запуск из планировщика), автоматическая установка включается сама.
#
# Необязательная переменная:
#   XUI_SH_URL=...   откуда брать x-ui.sh (по умолчанию из репозитория byDGer/3xui-keenetic-aarch64)
set -eu

XUI_SH_URL="${XUI_SH_URL:-https://raw.githubusercontent.com/byDGer/3xui-keenetic-aarch64/main/x-ui.sh}"
PANEL_REPO="MHSanaei/3x-ui"   # панель всегда скачивается отсюда
DIR=/opt/etc/x-ui
WORK=/opt/tmp

# Сообщение об ошибке и выход
die() { echo "Ошибка: $*" >&2; exit 1; }

# Всё тело скрипта лежит в функции main и вызывается в самом конце: так sh прочитает файл целиком
# до начала выполнения (важно при запуске через "curl | sh").
main() {
  # Отвязываем стандартный ввод: дочерние команды не должны «съесть» остаток скрипта из канала
  exec </dev/null

  # --- 1. Проверки окружения ---
  [ "$(id -u)" -eq 0 ] || die "нужен root"
  [ -x /opt/bin/opkg ] || die "не найден Entware (/opt/bin/opkg). Включите компонент OPKG и установите Entware."
  case "$(uname -m)" in
    aarch64|arm64) ;;
    *) die "архитектура $(uname -m): скрипт рассчитан на aarch64 (у 3x-ui нет сборок под MIPS)" ;;
  esac
  [ ! -x "$DIR/xui" ] || die "3x-ui уже установлена. Для управления и обновления запустите: x-ui"
  export PATH=/opt/sbin:/opt/bin:$PATH   # x-ui.sh требует, чтобы opkg был именно /opt/bin/opkg

  # --- 2. Пакеты, нужные для запуска x-ui.sh (остальное x-ui.sh доустановит сам) ---
  echo "==> Устанавливаю зависимости"
  opkg update
  opkg install curl ca-certificates wget-ssl bash
  if opkg list-installed | grep -q '^wget-nossl '; then opkg remove wget-nossl; fi

  # --- 3. Скачиваю управляющий скрипт x-ui.sh ---
  echo "==> Скачиваю x-ui.sh"
  mkdir -p "$WORK"
  cd "$WORK"
  rm -f x-ui.sh
  curl -fsSL "$XUI_SH_URL" -o x-ui.sh || die "не удалось скачать $XUI_SH_URL"
  head -n 1 x-ui.sh | grep -q '^#!' || die "скачанный файл не похож на скрипт"
  # Проверка: панель в этом скрипте должна качаться именно с MHSanaei/3x-ui
  grep -q "github.com/$PANEL_REPO/releases/download" x-ui.sh \
    || die "в скачанном x-ui.sh панель скачивается не с $PANEL_REPO"
  # В скрипте должен быть режим автоматической установки
  grep -q '^auto_install()' x-ui.sh || die "в скачанном x-ui.sh нет режима auto_install (нужна версия 1.0.3 или новее)"

  # --- 4. Запуск x-ui.sh ---
  rc=0
  if [ "${1:-}" = "auto" ]; then
    # Явно попросили автоматическую установку: выбор не показываем
    echo "==> Запускаю автоматическую установку"
    bash ./x-ui.sh auto_install || rc=$?
  elif ( : </dev/tty ) 2>/dev/null; then
    # Стандартный ввод занят самим скриптом (curl | sh), поэтому клавиатуру подключаем явно через /dev/tty:
    # x-ui.sh покажет выбор «автоматическая установка / самостоятельная настройка»
    echo "==> Запускаю x-ui.sh"
    bash ./x-ui.sh </dev/tty || rc=$?
  else
    echo "==> Терминал недоступен, выбор показать нельзя: запускаю автоматическую установку"
    bash ./x-ui.sh auto_install || rc=$?
  fi
  rm -f "$WORK/x-ui.sh"   # если скрипт не перенёс себя в /opt/etc/x-ui, убираем временный файл
  [ "$rc" -eq 0 ] || die "установка завершилась с ошибкой (код $rc). Журнал: /opt/var/log/script_x-ui.log"
}

main "$@"
