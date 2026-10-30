#!/bin/sh
# install-3xui-keenetic.sh: автоматическая установка ПОСЛЕДНЕЙ версии 3x-ui на Keenetic
# (Entware, aarch64). Панель всегда скачивается из github.com/MHSanaei/3x-ui,
# управляющий скрипт x-ui.sh берётся из x-ui-keenetic (GitLab).
#
# Запуск одной командой (на роутере, по SSH в Entware, от root):
#   curl -fsSL https://raw.githubusercontent.com/dgerankin/3xui-keenetic-aarch64/main/install-3xui-keenetic.sh | sh
# Нужны curl и ca-certificates:  opkg update && opkg install curl ca-certificates
#
# Необязательная переменная:
#   XUI_SH_URL=...   откуда брать управляющий скрипт x-ui.sh
#                    (по умолчанию GitLab own-open-source/x-ui-keenetic)
set -eu

XUI_SH_URL="${XUI_SH_URL:-https://gitlab.com/own-open-source/x-ui-keenetic/-/raw/main/x-ui.sh}"
PANEL_REPO="MHSanaei/3x-ui"

DIR=/opt/etc/x-ui
WORK=/opt/tmp

die() { echo "Ошибка: $*" >&2; exit 1; }

main() {
  # скрипт читается из stdin (curl | sh): отвязываем stdin, чтобы дочерние команды не съели остаток
  exec </dev/null

  # --- 1. Проверки ---
  [ "$(id -u)" -eq 0 ] || die "нужен root"
  [ -x /opt/bin/opkg ] || die "не найден Entware (/opt/bin/opkg). Включите компонент OPKG и установите Entware."
  case "$(uname -m)" in
    aarch64|arm64) ;;
    *) die "архитектура $(uname -m): скрипт рассчитан на aarch64 (у 3x-ui нет сборок под MIPS)" ;;
  esac
  [ ! -x "$DIR/xui" ] || die "3x-ui уже установлена. Для обновления используйте меню: x-ui"
  export PATH=/opt/sbin:/opt/bin:$PATH   # x-ui.sh требует, чтобы opkg был именно /opt/bin/opkg

  # --- 2. Пакеты ---
  echo "==> Устанавливаю зависимости"
  opkg update
  opkg install curl ca-certificates wget-ssl bash
  if opkg list-installed | grep -q '^wget-nossl '; then opkg remove wget-nossl; fi

  # --- 3. Последняя версия 3x-ui ---
  echo "==> Определяю последнюю версию 3x-ui"
  TAG="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$PANEL_REPO/releases/latest" 2>/dev/null \
    | sed -n 's|.*/releases/tag/\(.*\)|\1|p')"
  if [ -z "$TAG" ]; then   # запасной вариант: GitHub API
    TAG="$(curl -fsSL "https://api.github.com/repos/$PANEL_REPO/releases/latest" 2>/dev/null \
      | grep '"tag_name":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')"
  fi
  [ -n "$TAG" ] || die "не удалось определить последнюю версию $PANEL_REPO"
  ASSET="https://github.com/$PANEL_REPO/releases/download/$TAG/x-ui-linux-arm64.tar.gz"
  curl -fsIL "$ASSET" >/dev/null 2>&1 || die "в релизе $TAG нет файла x-ui-linux-arm64.tar.gz ($ASSET)"
  echo "    Последняя версия: $TAG"

  # --- 4. Скачиваю управляющий скрипт x-ui.sh ---
  echo "==> Скачиваю x-ui.sh"
  mkdir -p "$WORK"
  cd "$WORK"
  rm -f x-ui.sh
  curl -fsSL "$XUI_SH_URL" -o x-ui.sh \
    || die "не удалось скачать $XUI_SH_URL"
  head -n 1 x-ui.sh | grep -q '^#!' || die "скачанный файл не похож на скрипт"
  # панель должна качаться именно с MHSanaei/3x-ui
  grep -q "github.com/$PANEL_REPO/releases/download" x-ui.sh \
    || die "в скачанном x-ui.sh панель скачивается не с $PANEL_REPO"

  # --- 5. Патчи (проверяются, чтобы молча не пропустить изменение формата скрипта) ---
  # 5a. Не возвращаться в интерактивное меню после установки (3-й аргумент install)
  sed -i 's|safe_call_function "\$call" \$NAME_APP "\$RECCOMMENDED_VERSION"|& 1|' x-ui.sh
  grep -q 'RECCOMMENDED_VERSION" 1' x-ui.sh \
    || die "не удалось применить патч «без меню»: формат x-ui.sh отличается от ожидаемого"
  # 5b. Ставить найденную последнюю версию, а не зашитую в скрипте
  sed -i "s|^RECCOMMENDED_VERSION=.*|RECCOMMENDED_VERSION=\"${TAG#v}\"|" x-ui.sh
  grep -q "^RECCOMMENDED_VERSION=\"${TAG#v}\"" x-ui.sh || die "не удалось подставить версию $TAG"
  cp x-ui.sh x-ui.sh.src   # x-ui.sh переносит сам себя в $DIR; копия на случай, если этого не случится

  # --- 6. Установка: все вопросы проходим значениями по умолчанию ---
  # (порт 2053, путь /spub/, прослушивание LAN-адреса br0, без SSL; логин/пароль сменим ниже)
  echo "==> Устанавливаю панель $TAG"
  printf '\n\n\n\n\n\n\n\n\n\n' > answers.txt
  bash ./x-ui.sh install < answers.txt || true
  rm -f answers.txt

  [ -x "$DIR/xui" ] || die "панель не установилась (нет $DIR/xui). Журнал: /opt/var/log/script_x-ui.log"
  [ -f "$DIR/x-ui.sh" ] || cp x-ui.sh.src "$DIR/x-ui.sh"
  chmod +x "$DIR/x-ui.sh"
  [ -e /opt/bin/x-ui ] || ln -s "$DIR/x-ui.sh" /opt/bin/x-ui

  # --- 7. Случайные учётные данные вместо admin/12345 ---
  export ZONEINFO=/opt/share/zoneinfo
  export XUI_BIN_FOLDER="$DIR/bin" XUI_DB_FOLDER="$DIR/db"
  export XUI_LOG_FOLDER=/opt/var/log/x-ui XUI_LOG_LEVEL=error XUI_DEBUG=false

  rand() { tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$1"; }
  USER_NAME="$(rand 8)"
  USER_PASS="$(rand 16)"
  BASE_PATH="/$(rand 10)/"
  "$DIR/xui" setting -username "$USER_NAME" -password "$USER_PASS" \
    -webBasePath "$BASE_PATH" -resetTwoFactor false >/dev/null

  # --- 8. Автозапуск и старт ---
  bash "$DIR/x-ui.sh" enable
  bash "$DIR/x-ui.sh" start
  rm -rf "$DIR/new"      # иначе при первом открытии меню x-ui повторно спросит про запуск
  rm -f "$WORK/x-ui.sh" "$WORK/x-ui.sh.src"

  # --- 9. Итог ---
  PORT="$("$DIR/xui" setting -show 2>/dev/null | grep -Eo 'port: .+' | awk '{print $2}' | head -n 1)"
  LAN_IP="$(ifconfig br0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')"
  echo
  echo "###############################################"
  echo "3x-ui $TAG установлена."
  echo "Адрес:  http://${LAN_IP:-<IP роутера>}:${PORT:-2053}${BASE_PATH}"
  echo "Логин:  $USER_NAME"
  echo "Пароль: $USER_PASS"
  echo "###############################################"
  echo "Сохраните данные: повторно они не показываются. Меню управления: x-ui"
}

main "$@"
