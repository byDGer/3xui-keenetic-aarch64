#!/opt/bin/bash

# START VARIABLES  ------------------------------------------------------------
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

declare -A ICO_MAP=( [GOOD]="[ ✔ ]" [BAD]="[ ✘ ]" [WORK]="[ ⚙ ]" [INF]="[INF]" [ERR]="[ERR]" [WAR]="[⚠️]" )

RECCOMMENDED_VERSION="2.8.5"
CURRENT_VERSION_SCRIPT="1.0.0"
CURRENT_VERSION_PANEL=""
LAST_VERSION_PANEL=""
LAST_VERSION_SCRIPT=""
CURRENT_VERSION_ALL=""


NAME_APP=xui
PRIORITY="S99"
SHELL_SHORT_NAME="x-ui"
SHELL_FULL_NAME="$SHELL_SHORT_NAME.sh"

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
DIR_CONFIG="$DIR_PROJECT/config"

DB="$DIR_DB/$SHELL_SHORT_NAME.db"

NAME_NOTREAL_SHELL=$(basename "$0")
DEFAULT_EDITOR="nano"
ARCHITECTURE=""
COMMANDS_CALL=""

DEBUG_SCRIPT=false
LOG_SCRIPT=true
XUI_BIN_FOLDER="$DIR_PROJECT/bin"
XUI_DB_FOLDER="$DIR_DB"
XUI_LOG_FOLDER="$DIR_ENTWARE/var/log/$SHELL_SHORT_NAME"
XUI_LOG_LEVEL="error" # possible values: debug, info, notice, warning, error
XUI_DEBUG="false"
declare -A map_confirm
# END VARIABLES ------------------------------------------------------------
# START PREPARATION --------------------------------------------------------
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
		echo -e "XUI_BIN_FOLDER=\"$XUI_BIN_FOLDER\"" >> "$DIR_CONFIG/settings"
		echo -e "XUI_DB_FOLDER=\"$XUI_DB_FOLDER\"" >> "$DIR_CONFIG/settings"
		echo -e "XUI_LOG_FOLDER=\"$XUI_LOG_FOLDER\"" >> "$DIR_CONFIG/settings"
		echo -e "XUI_LOG_LEVEL=\"$XUI_LOG_LEVEL\"" >> "$DIR_CONFIG/settings"
		echo -e "XUI_DEBUG=\"$XUI_DEBUG\"" >> "$DIR_CONFIG/settings"
	fi
fi

export ZONEINFO=/opt/share/zoneinfo
export XUI_BIN_FOLDER="$XUI_BIN_FOLDER"
export XUI_DB_FOLDER="$XUI_DB_FOLDER"
export XUI_LOG_FOLDER="$XUI_LOG_FOLDER"
export XUI_LOG_LEVEL="$XUI_LOG_LEVEL"
export XUI_DEBUG="$XUI_DEBUG"

strip_ansi() {
    sed -E $'s/\x1B\[[0-9;?]*[ -/]*[@-~]//g; s/\033\[[0-9;?]*[ -/]*[@-~]//g; s/\e\[[0-9;?]*[ -/]*[@-~]//g; s/\x1B//g; s/\033//g; s/\e//g'
}

logmsg() {
    local msg="$1"
    local onlylog="$2"
    local stack=""
    local i
    
    for ((i=${#FUNCNAME[@]}-1; i>0; i--)); do
        stack+="${FUNCNAME[$i]}"
        if [[ $i -ne 1 ]]; then
            stack+=" ${color_cyan}->${style_plain} "
        fi
    done
    stack=$(echo -e "$stack" | sed -E 's/[[:space:]]*->[[:space:]]*$//')
    if [[ "$LOG_SCRIPT" == true ]]; then
        local now
        now="$(date '+%Y-%m-%d %H:%M:%S')"
        echo -e "[$now] [TRACE] $(echo -e "$stack" | strip_ansi)" >> "$DIR_LOGFILE"
        echo -e "[$now] [MESSAGE]$(echo -e "$msg" | strip_ansi)" >> "$DIR_LOGFILE"
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

DIR_REAL_SHELL=$(real_dir_shell)

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

check_os_release() {
    local release_path=$(command -v opkg)
    if  [[ "$release_path" != "/opt/bin/opkg" ]]; then
        logmsg "${color_red}Unsupported the system OS!${style_plain}" && rm -f "$SHELL_FULL_NAME" && exit 1
    fi
    release="entware"
    if [[ -z $1 ]]; then
        logmsg "${ICO_MAP[GOOD]} The OS release is: $release"
    fi
}
check_architecture() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) ARCHITECTURE='amd64' ;;
        i*86 | x86) ARCHITECTURE='386' ;;
        armv8* | armv8 | arm64 | aarch64) ARCHITECTURE='arm64' ;;
        armv7* | armv7 | arm) ARCHITECTURE='armv7' ;;
        armv6* | armv6) ARCHITECTURE='armv6' ;;
        armv5* | armv5) ARCHITECTURE='armv5' ;;
        s390x) ARCHITECTURE='s390x' ;;
        *) logmsg "${color_red}Unsupported CPU architecture! ${style_plain}" && rm -f "$SHELL_FULL_NAME" && exit 1 ;;
    esac
    if [[ -z $1 ]]; then
        logmsg "${ICO_MAP[GOOD]} ARCHITECTURE: $ARCHITECTURE"
    fi  
}
# END PREPARATION ------------------------------------------------------------
# START INSTALLATION ------------------------------------------------------------
get_menu_word() {
    local menu="$1"
    local number="$2"
    echo "$menu" \
      | sed -E 's/\x1B\[[0-9;?]*[ -/]*[@-~]//g' \
      | grep -E "\(${number}\)" \
      | sed -E 's/.*\[([A-Za-z0-9_.]+).*/\1/' \
      | tr '[:upper:]' '[:lower:]'
}

install_base() {
    check_architecture
    logmsg "${ICO_MAP[WORK]} ${color_green}Checking preparation... not panic! ;) ${style_plain}"
    sleep 1
    case "${release}" in
    entware)
        opkg update && opkg install wget curl tar wget-ssl ca-certificates sqlite3-cli jq openssl-util libopenssl
        ;;
    *) logmsg "${color_red}Unsupported release! ${release}" && rm -f "$SHELL_FULL_NAME" && exit 1
		;;
    esac
}

migration(){
    logmsg "${ICO_MAP[WORK]} ${color_yellow}Migration... ${style_plain}"
    $DIR_PROJECT/$NAME_APP migrate
    logmsg "${ICO_MAP[GOOD]} ${color_yellow}Migration finished!${style_plain}"
}

config_after_install() {
    exe_set_panel
    exe_set_admin
}

prepare_services() {
    if [[ -d $DIR_PROJECT ]]; then
        find $DIR_PROJECT -type f,d  -not \( -name "$SHELL_FULL_NAME" -or -name 'db' \) -delete
    fi
    if [[ -f "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME" ]]; then
        rm "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME" -f
    fi
    if [[ -f $DIR_INSTALL_LNK ]]; then
        rm $DIR_INSTALL_LNK -f
    fi
}

check_show_main_menu(){
    if [[ -n "$show_main_menu" ]]; then
        before_show_main_menu
        return 0
    fi
}

menu_choice(){
local menu=$1
local choice=$2
local txt=${3:-"Please enter your selection"}
local default_choice=$( [ -n "$4" ] && echo " [default: $4]" || echo "" )
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

update_panel(){
    check_install
    last_version_checked "$NAME_APP"
    if [[ "v$CURRENT_VERSION_PANEL" == "$LAST_VERSION_PANEL" ]]; then
        logmsg "${color_green}You are already using the latest version $NAME_APP: v${CURRENT_VERSION_PANEL}${style_plain}"
    else
        logmsg "${color_yellow}A new version $NAME_APP is available: ${LAST_VERSION_PANEL}, you are using: v${CURRENT_VERSION_PANEL}${style_plain}"
        confirm_options "This function will forcefully reinstall the latest version $NAME_APP, and the data will not be lost. Do you want to continue"
        if [ $? == 0 ]; then
            logmsg "${color_bg_white}Beginning the update $NAME_APP..."
            install $NAME_APP $LAST_VERSION_PANEL $1
        fi
    fi
}

update_script(){
    check_install
    last_version_checked "script"
    if [[ "$CURRENT_VERSION_SCRIPT" == "$LAST_VERSION_SCRIPT" ]]; then
        logmsg "${color_green}You are already using the latest version script: ${CURRENT_VERSION_SCRIPT}${style_plain}"
    else
        logmsg "${color_yellow}A new version script is available: ${LAST_VERSION_SCRIPT}, you are using: ${CURRENT_VERSION_SCRIPT}${style_plain}"
        confirm_options "This function will forcefully reinstall the latest version script, and the data will not be lost. Do you want to continue"
        if [ $? == 0 ]; then
            logmsg "${color_bg_white}Beginning the update script..."
            install script $LAST_VERSION_SCRIPT $1
        fi
    fi
}
            
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

update(){
    check_install
    menu_choice menu_update "$1" "Please choose an update you want to perform"
    safe_call_function "$schoice"
}

last_version_checked(){
    if [[ "$LAST_VERSION_SCRIPT" == "" && $1 == "script" ]]; then
        LAST_VERSION_SCRIPT=$(curl -s https://gitlab.com/own-open-source/x-ui-keenetic/-/releases/permalink/latest | grep -m1 -Eo "releases/[^/]+\"" | awk 'BEGIN { FS="/" } {print $2}' | rev | cut -c2- | rev)
        return 1
    fi
    if [[ "$LAST_VERSION_PANEL" == "" && $1 == "$NAME_APP" ]]; then
        LAST_VERSION_PANEL=$(curl -4 -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        return 1
    fi
    return 0
}

download_proc() {
    check_architecture 1
    local version_type=$2
    local type="${1,,}"
    local version_to_check
    
    if [[ $type == "script" ]]; then
        version_to_check="${version_type}${LAST_VERSION_SCRIPT}"
        url="https://gitlab.com/own-open-source/x-ui-keenetic/-/archive/${version_to_check}/x-ui-keenetic-${version_to_check}.tar.gz"
    fi
    if [[ $type == "${NAME_APP,,}" ]]; then
        version_to_check="${version_type}${LAST_VERSION_PANEL}"
        url="https://github.com/MHSanaei/3x-ui/releases/download/${version_to_check}/x-ui-linux-${ARCHITECTURE}.tar.gz"
    fi
    
    wget --no-check-certificate -O $DIR_TMP/"$SHELL_SHORT_NAME"-"$type".tar.gz "${url}"
    if [[ $? -ne 0 ]]; then
        if [[ $version_to_check != v* && -z $version_type ]]; then
            logmsg "${ICO_MAP[GOOD]} Try download again with ${color_magenta}v${style_plain}"
            download_proc $type "v"
            return $?
        elif [[ $version_to_check == v* && -z $version_type ]]; then
            logmsg "${ICO_MAP[GOOD]} Try download again without ${color_magenta}v${style_plain}"
            download_proc $type ""
            return $?
        else 
            return 1
        fi
    else
        return 0
    fi
}

clear_all_cache(){
    confirm_options "Do you really want to delete all cache files"
    if [[ $? == 0 ]]; then
        clear_cache && logmsg "${ICO_MAP[GOOD]} ${color_green}All cache cleared.${style_plain}"
    fi
}

clear_cache(){
    if [[ -d "$DIR_CACHE" ]]; then
        logmsg "${ICO_MAP[WORK]} ${color_green}Clearing cache...${style_plain}"
        rm -rf "$DIR_CACHE" 2>/dev/null
    fi
}

install() {
    if check_status 2>/dev/null; [[ $? -eq 2 ]]; then
        check_os_release && install_base
    fi
    if [[ ! -d "$DIR_PROJECT/new" ]]; then
        check_status
        if [[ $? == 0 ]]; then
            $SHELL_SHORT_NAME stop 1
        fi
        clear_cache && delete_config
    fi
    logmsg "${ICO_MAP[WORK]} ${color_green}Checking repository availability...${style_plain}"
    cd $DIR_TMP || return
    if [[ -z $2 ]]; then
        last_version_checked $1
    fi
    if [[ $1 == "$NAME_APP" ]]; then
        LAST_VERSION_PANEL=${LAST_VERSION_PANEL#v}
        if [ $# == 0 ]; then
            if [[ ! -n "$LAST_VERSION_PANEL" ]]; then
                logmsg "${ICO_MAP[BAD]} ${color_red}Failed to fetch $SHELL_SHORT_NAME version, please try it later${style_plain}"
                return
            fi
            logmsg "${ICO_MAP[GOOD]} Got $SHELL_SHORT_NAME latest version: ${color_magenta}${LAST_VERSION_PANEL}${style_plain}, beginning the installation..."
            download_proc $1
            if [[ $? -ne 0 ]]; then
                logmsg "${ICO_MAP[BAD]} ${color_red}Downloading $SHELL_SHORT_NAME failed${style_plain}"
                return
            fi
        else
            LAST_VERSION_PANEL=$2
            logmsg "${ICO_MAP[WORK]} Beginning the install ${color_magenta}$SHELL_SHORT_NAME $LAST_VERSION_PANEL${style_plain}"
            download_proc $1
            if [[ $? -ne 0 ]]; then
                logmsg "${ICO_MAP[BAD]} ${color_red}download $SHELL_SHORT_NAME $LAST_VERSION_PANEL failed,please check the version exists: ${url}${style_plain}"
                return
            fi
        fi
        tar zxvf $SHELL_SHORT_NAME-"$1".tar.gz
        mv $SHELL_SHORT_NAME/$SHELL_SHORT_NAME $SHELL_SHORT_NAME/$NAME_APP
        if [[ $ARCHITECTURE == "armv5" || $ARCHITECTURE == "armv6" || $ARCHITECTURE == "armv7" ]]; then
            mv bin/xray-linux-$ARCHITECTURE bin/xray-linux-arm
        fi
		rm -rf $DIR_TMP/$SHELL_SHORT_NAME/x-ui.service 2>/dev/null
        chmod -R 755 $SHELL_SHORT_NAME/$NAME_APP
        cp -rf $DIR_TMP/$SHELL_SHORT_NAME $DIR_MAIN
        if [[ ! -f $DB ]]; then
            config_after_install
        else
            migration
        fi
        logmsg "${ICO_MAP[GOOD]} ${color_green}$SHELL_SHORT_NAME $LAST_VERSION_PANEL${style_plain} installation finished..."
        logmsg "You may access the Panel with following URL(s):${color_green}"
        view_panel
        check_all_ruls 1 2>/dev/null
        rm -rf $SHELL_SHORT_NAME 2>/dev/null
    elif [[ $1 == "script" ]]; then
        if [ $# == 0 ]; then
            if [[ ! -n "$LAST_VERSION_SCRIPT" ]]; then
                logmsg "${ICO_MAP[BAD]} ${color_red}Failed to fetch script version, please try it later${style_plain}"
                return
            fi
            logmsg "${ICO_MAP[GOOD]} Got script latest version: ${LAST_VERSION_SCRIPT}, beginning the installation..."
            download_proc $1
            if [[ $? -ne 0 ]]; then
                logmsg "${ICO_MAP[BAD]} ${color_red}Downloading script failed${style_plain}"
                return
            fi
        else
            LAST_VERSION_SCRIPT=$2
            logmsg "${ICO_MAP[WORK]} Beginning the install script ${color_magenta}$LAST_VERSION_SCRIPT${style_plain}"
            download_proc $1
            if [[ $? -ne 0 ]]; then
                logmsg "${ICO_MAP[BAD]} ${color_red}download script $LAST_VERSION_SCRIPT failed,please check the version exists: ${url}${style_plain}"
                return
            fi
        fi
        tar zxvf $SHELL_SHORT_NAME-"$1".tar.gz
        mv -f -- $DIR_TMP/$SHELL_SHORT_NAME-keenetic-${LAST_VERSION_SCRIPT}/$SHELL_FULL_NAME $DIR_PROJECT_SHELL_SCRIPTS
        rm -rf $DIR_TMP/$SHELL_SHORT_NAME-keenetic-${LAST_VERSION_SCRIPT}
    else
        logmsg "${ICO_MAP[BAD]} ${color_red}Unknown installation type: $1${style_plain}"
        return
    fi
    rm $SHELL_SHORT_NAME-"$1".tar.gz -f
    permissions
    logmsg "${ICO_MAP[GOOD]} ${style_reverse}$1 version ${LAST_VERSION_PANEL} installed successfully!${style_plain}"
    logmsg "${style_reverse}To access the script, type: $SHELL_SHORT_NAME${style_plain}"
    it_was_updated=1 && mkdir -p "$DIR_PROJECT/new"
    if [[ -z $3 ]]; then
        before_show_main_menu $DIR_PROJECT_SHELL_SCRIPTS
    fi
}

custom() {
    if [[ -z "$2" ]]; then
        confirm_options "Enter the $1 version (like 0.0.1)" "" "panel_version_$1"  $color_cyan
    else
        map_confirm["panel_version_$1"]=$2
    fi
    if [ -z "${map_confirm[panel_version_$1]}" ]; then
        echo "Panel version cannot be empty!"
		return 1
    fi
	install $1 "${map_confirm[panel_version_$1]}" "$3"
}

install_custom_PANEL(){
    custom $NAME_APP "" 1
}

install_custom_script(){
    custom script "" 1
}

install_custom(){
    menu_choice menu_install_custom "$1"
    safe_call_function "$schoice"
    if [[ -n $it_was_updated ]]; then
        before_show_main_menu $DIR_PROJECT_SHELL_SCRIPTS
    fi
}

uninstall() {
    if [[ ! -f $DIR_PROJECT/$NAME_APP ]]; then
    logmsg "${color_red}The panel is not installed!${style_plain}"
	else
		confirm_options "Are you sure you want to uninstall the panel" "n" "" "$color_red"
		if [[ $? == 0 ]]; then
            if [[ -d $DIR_PROJECT ]]; then
            logmsg "${color_yellow}Uninstalling... ${style_plain}"
            stop && disable
            rm -rf "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME"
            rm -rf $DIR_INSTALL_LNK
            rm -rf $DIR_PROJECT
            logmsg "${color_yellow}Uninstalled Successfully${style_plain}"
            logmsg "${color_yellow}Log was saved to $DIR_LOGFILE!${style_plain}"
            logmsg "${color_yellow}For deletion:${style_plain} ${color_magenta}rm -rf $DIR_LOGFILE${style_plain}"
			echo "$SHELL_SHORT_NAME was" && kill -9 $$
			else
                logmsg "${color_red}The panel is not installed! ${style_plain}"
			fi
		fi
	fi
}
# END INSTALLATION ------------------------------------------------------------
# START PANEL COMMANDS ---------------------------------------------------------
safe_call_command() {
    if [ $# -lt 1 ]; then
        logmsg "${color_red}${ICO_MAP[ERR]} No command given to safe_call_command ${style_plain}"
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
                local raw_err="${script_name}: line ${lineno}: ${cmd}: command not found"
                echo "[$now] [ERR] $raw_err" >> "$DIR_LOGFILE" 2>/dev/null
            fi
            logmsg "${color_red}${ICO_MAP[ERR]} $raw_err${style_plain}"
            return 127
        fi
    fi
}

safe_call_function() {
    if [ $# -lt 1 ]; then
        logmsg "${color_red}${ICO_MAP[ERR]} No command given to safe_call_function${style_plain}"
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
            local raw_err="${script_name}: line ${lineno}: ${cmd}: function not found"
            echo "[$now] [ERR] $raw_err" >> "$DIR_LOGFILE" 2>/dev/null
        fi
        logmsg "${color_red}${ICO_MAP[ERR]} $raw_err${style_plain}"
        return 127
    fi
}

confirm_options() {
    local question=$1
    local default=$2
    local confirm_type=""
    local txtcolor=${4:-$color_magenta}
    logmsg "question: $question, default: $default, confirm_type: $confirm_type, txtcolor: $txtcolor" nolog
    echo ""
    if [[ -z "$3" ]]; then
        confirm_type="[y/n]"
    fi
    if [[ -n "$default" ]]; then
        echo -n -e "${txtcolor}$question $confirm_type? [default: $default]:${style_plain}" && read -p " " temp
        if [[ "${temp}" == "" ]]; then
            temp=$default
        fi
    else
        echo -n -e "${txtcolor}$question $confirm_type?:${style_plain} " && read -p " " temp
    fi
    logmsg "Choice: $temp" nolog
    if [[ -n "$confirm_type" ]]; then
        if [[ "${temp^^}" == "Y" ]]; then
            return 0
        else
            return 1
        fi
    else
        if [[ -n "$3" ]]; then
            map_confirm["$3"]="$temp"
        else
            logmsg "${color_red}${ICO_MAP[ERR]} No variable name provided for storing the input.${style_plain}"
            exit 1
        fi
    fi
}

confirm_restart() {
    confirm_options "Restart the $SHELL_SHORT_NAME service" "y"
    if [[ $? == 0 ]]; then
        restart
    fi
}

reset_admin() {
    confirm_options "Are you sure you want to reset admin's credentials to default" "n"
    if [[ $? == 0 ]]; then
        local usernameTemp=$(head -c 6 /dev/urandom | base64)
        local passwordTemp=$(head -c 6 /dev/urandom | base64)
        exe_set_admin "$usernameTemp" "$passwordTemp" "true"
        logmsg "${color_red}${ICO_MAP[INF]} Admin's credentials have been reset to default${style_plain}"
		show_admin "$usernameTemp" "$passwordTemp"
        confirm_restart
    fi
}

show_admin() {
    echo -e "###############################################"
    echo -e "${color_green}Username: ${1}${style_plain}"
    echo -e "${color_green}Password: ${2}${style_plain}"
    echo -e "###############################################"
}

exe_set_admin() {
        confirm_options "Please set up your username" "${1:-admin}" "config_account"  $color_cyan
        confirm_options "Please set up your password" "${2:-12345}" "config_password" $color_cyan
		confirm_options "Do you want to disable currently configured two-factor authentication" "${3:-false}" "config_authentication" $color_cyan
        $DIR_PROJECT/$NAME_APP setting -username ${map_confirm[config_account]} -password ${map_confirm[config_password]} -resetTwoFactor ${map_confirm[config_authentication]}
		show_admin "${map_confirm[config_account]}" "${map_confirm[config_password]}"
}

set_admin() {
    confirm_options "Are you sure you want to set admin's credentials" "n"
    if [[ $? == 0 ]]; then
        exe_set_admin
        logmsg "${color_red}${ICO_MAP[INF]} Admin's credentials have been set${style_plain}"
        confirm_restart
    fi
}

reset_panel() {
    confirm_options "Are you sure you want to reset all panel settings. Account data will not be lost. Username and password will not change" "n"
    if [[ $? == 0 ]]; then
        $DIR_PROJECT/$NAME_APP setting -reset
        logmsg "${ICO_MAP[INF]}All panel settings have been reset to default!" && view_panel && confirm_restart
    fi
}

restart() {
    $SHELL_SHORT_NAME stop 1 && sleep 1 && $SHELL_SHORT_NAME start 1 && sleep 1
    check_status; local status=$?
    [[ $status == 0 ]] && logmsg "${color_green}${ICO_MAP[INF]} $SHELL_SHORT_NAME Restarted successfully${style_plain}" || logmsg "${color_red}${ICO_MAP[ERR]}Failed to restart $SHELL_SHORT_NAME, Probably because it takes longer than two seconds to start, Please check the log information later${style_plain}"
}

ssl_check(){
	local certs=$($DIR_PROJECT/$NAME_APP setting -getCert)
	if [[ -z "$certs" ]]; then
		logmsg "${color_yellow}SSL certificate is not configured now!${style_plain}"
	else
		logmsg "${color_green}SSL certificate is configured properly:${style_plain}"
    	echo -e "\n###############################################\n"
    	echo -e "                 SSL IN PANEL"
		logmsg "$certs"
    	echo -e "\n###############################################\n"
	fi

    confirm_options "Do you want to set an SSL certificate for the panel" "n"
    if [[ $? == 0 ]]; then
    	local count=$(ls -1 "$DIR_CERT"/*.* 2>/dev/null | wc -l)
		if [[ $count -ge 2 ]]; then
			logmsg "We found $count cert files in $DIR_CERT/"
			ls -l "$DIR_CERT"
		fi
		confirm_options "Enter the panel webCert public" "$DIR_CERT/webCert.pem" "config_webCert" $color_cyan
		confirm_options "Enter the panel webCertKey private" "$DIR_CERT/webCertKey.pem" "config_webCertKey" $color_cyan
		local params=""
		[ -z "${map_confirm[config_webCert]}" ] || params="$params -webCert ${map_confirm[config_webCert]}"
		[ -z "${map_confirm[config_webCertKey]}" ] || params="$params -webCertKey ${map_confirm[config_webCertKey]}"
		logmsg "${color_yellow}Initializing, please wait...${style_plain}"
		$DIR_PROJECT/$NAME_APP cert ${params}
		echo -e "" && logmsg "${color_green}Initializing complete!${style_plain}"	
		return 0
	fi
	return 1
}

exe_set_panel() {
	confirm_options "Enter the panel port" "2053" "config_port" $color_cyan
	confirm_options "Enter the panel path" "/spub/" "config_path" $color_cyan
	confirm_options "Enter the listen IP" "$(ifconfig br0 | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')" "config_listenIP" $color_cyan
	logmsg "${color_yellow}Initializing, please wait...${style_plain}"
	local params=""
	[ -z "${map_confirm[config_port]}" ] || params="$params -port ${map_confirm[config_port]}"
	[ -z "${map_confirm[config_path]}" ] || params="$params -webBasePath ${map_confirm[config_path]}"
	[ -z "${map_confirm[config_listenIP]}" ] || params="$params -listenIP ${map_confirm[config_listenIP]}"
	$DIR_PROJECT/$NAME_APP setting ${params}
	echo -e "" && logmsg "${color_green}Initializing complete!${style_plain}"
    if [[ -z $1 ]]; then
		confirm_options "Do you want to check and change the SSL certificate" "n"
		if [[ $? -eq 0 ]]; then
			ssl_check
		fi
	fi
	return 0
}

set_panel() {
    confirm_options "Are you sure you want to set panel settings" "n"
    if [[ $? == 0 ]]; then
        exe_set_panel && confirm_restart
    fi
}

view_panel() {
   local info=$("$DIR_PROJECT/$NAME_APP" setting -show)
    if [[ $? != 0 ]]; then
        logmsg "get current settings error, please check logs"
        return
    fi
	local existing_cert_path=$("$DIR_PROJECT/$NAME_APP" setting -getCert)
	local existing_ip=$($DIR_PROJECT/$NAME_APP setting -getListen | grep -Eo 'listenIP: .+' | awk '{print $2}')
    local existing_webBasePath=$(echo "$info" | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(echo "$info" | grep -Eo 'port: .+' | awk '{print $2}')
    local existing_cert=$(echo "$existing_cert_path" | grep -Eo 'cert: .+' | awk '{print $2}')
    local server_ip=$(curl -s --max-time 3 https://api.ipify.org)
    if [ -z "$server_ip" ]; then
        server_ip=$(curl -s --max-time 3 https://4.ident.me)
    fi
    echo -e "\n###############################################\n"
	echo -e "In panel listen IP: $existing_ip\n"
	echo -e "$info\n"
	echo -e "$existing_cert_path\n"
    if [[ -n "$existing_cert" ]]; then
        local domain=$(basename "$(dirname "$existing_cert")")

        if [[ "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            echo -e "${green}Access URL: https://${domain}:${existing_port}${existing_webBasePath}${plain}\n"
        else
            echo -e "${green}Access URL: https://${server_ip}:${existing_port}${existing_webBasePath}${plain}\n"
        fi
    else
        echo -e "${green}Access URL: http://${server_ip}:${existing_port}${existing_webBasePath}${plain}\n"
    fi
	local localip=$(ifconfig br0 | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')
	if [[ -n "$localip" ]]; then
		echo -e "${green}Local Access URL: http://${localip}:${existing_port}${existing_webBasePath}${plain}\n"
	fi
    echo -e "###############################################"
}

start() {
    check_status; local status=$?
    if [[ $status == 0 ]]; then
        echo ""
        logmsg "${color_green}${ICO_MAP[INF]} $SHELL_SHORT_NAME is running, no need to start again!${style_plain}"
    else
        tmpfile=$(mktemp)
        nice -n -19 "$DIR_PROJECT/$NAME_APP" run >"$tmpfile" 2>&1 & disown
        output=$(cat "$tmpfile")
        echo "$output" >> "$DIR_LOGFILE"
        rm -f "$tmpfile"
        logmsg "${ICO_MAP[WORK]} loading..."
        sleep 1
        if ! check_panel; then
            logmsg "${ICO_MAP[BAD]} Error: $SHELL_SHORT_NAME failed to start"
        fi
        sleep 2
        check_status; local status2=$?
        [[ $status2 == 0 ]] && logmsg "${color_green}${ICO_MAP[INF]} $SHELL_SHORT_NAME started successfully${style_plain}" || logmsg "${color_red}${ICO_MAP[ERR]} failed to start $SHELL_SHORT_NAME, probably because it takes longer than two seconds to start, please check the log information later${style_plain}"
    fi
}

stop() {
    check_status; local status=$?
    if [[ $status == 1 ]]; then
        echo ""
        logmsg "${color_green}${ICO_MAP[INF]} $SHELL_SHORT_NAME stopped, no need to stop again!${style_plain}"
    else
        if killall $DIR_PROJECT/$NAME_APP 2>/dev/null; then
            killall -q -KILL $DIR_PROJECT/$NAME_APP
            logmsg "${ICO_MAP[GOOD]} $SHELL_SHORT_NAME stopped"
        else
            logmsg "${ICO_MAP[GOOD]} $SHELL_SHORT_NAME was already stopped!"
        fi
        sleep 2
        check_status; local status2=$?
        [[ $status2 == 1 ]] && logmsg "${color_green}${ICO_MAP[INF]} $SHELL_SHORT_NAME stopped successfully${style_plain}" || logmsg "${color_red}${ICO_MAP[ERR]}failed to stop $SHELL_SHORT_NAME, probably because the stop time exceeds two seconds, please check the log information later${style_plain}"
    fi
}

is_enabled() {
	status
}

check() {
	status
}

status() {
	if check_panel; then
    logmsg "${ICO_MAP[GOOD]}  $SHELL_SHORT_NAME running"
	else
    logmsg "${ICO_MAP[GOOD]}  $SHELL_SHORT_NAME stopped"
	fi
}

enable() {
    if [[ -L "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME" || -f "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME" ]]; then
        logmsg "${color_green}${ICO_MAP[INF]} $SHELL_SHORT_NAME was is enable${style_plain}"
    else
        ln -s "$DIR_PROJECT_SHELL_SCRIPTS" "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME"
        if [[ $? == 0 ]]; then
            logmsg "${color_green}${ICO_MAP[INF]} Set $SHELL_SHORT_NAME to boot automatically on startup successfully${style_plain}"
            dos2unix "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME" 2>/dev/null 
            chmod +x "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME" 2>/dev/null 
        else
            logmsg "${color_red}${ICO_MAP[ERR]} Failed to set $SHELL_SHORT_NAME Autostart${style_plain}"
        fi
    fi
}

disable() {
    if [[ ! -L "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME" && ! -f "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME" ]]; then
        logmsg "${color_green}${ICO_MAP[INF]} $SHELL_SHORT_NAME was disabled${style_plain}"
    else
        rm -rf "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME"
        if [[ $? == 0 ]]; then
            logmsg "${color_green}${ICO_MAP[INF]} Autostart $SHELL_SHORT_NAME Cancelled successfully${style_plain}"
        else
            logmsg "${color_red}${ICO_MAP[ERR]} Failed to cancel $SHELL_SHORT_NAME autostart${style_plain}"
        fi
    fi
}

editor(){
        confirm_options "We recommend using editor: $DEFAULT_EDITOR. Would you like to try it" "y"
        if [[ $? == 0 ]]; then
            opkg install $DEFAULT_EDITOR
        fi
}

edit_settings() {
    if [[ -f "$DIR_CONFIG/settings" ]]; then
        safe_call_command $DEFAULT_EDITOR $DIR_CONFIG/settings
        if [[ ! $? -eq 0 ]]; then
            logmsg "${color_yellow}${ICO_MAP[WAR]} Can't open settings file with $DEFAULT_EDITOR.${style_plain}"
            editor && safe_call_command $DEFAULT_EDITOR $DIR_CONFIG/settings
        fi
    else
        logmsg "${color_red}Settings file does not exist! ${style_plain}"
    fi
    logmsg "${color_red}${ICO_MAP[INF]} Settings file path: $DIR_CONFIG/settings${style_plain}"
}

log() {
    if [[ -f $DIR_LOGFILE ]]; then
        safe_call_command $DEFAULT_EDITOR $DIR_LOGFILE
        if [[ ! $? -eq 0 ]]; then
            logmsg "${color_yellow}${ICO_MAP[WAR]} Falling back to cat command for log viewing.${style_plain}"
            editor && safe_call_command $DEFAULT_EDITOR $DIR_LOGFILE
        fi
    else
        logmsg "${color_red}Log file does not exist! ${style_plain}"
    fi
    logmsg "${color_red}${ICO_MAP[INF]} Log file path: $DIR_LOGFILE${style_plain}"
}

check_status() {
	if [[ ! -f "$DIR_PROJECT/$NAME_APP" ]]; then
		return 2
	fi
	local temp=$( status | grep -o "running")
	if [[ "${temp,,}" == "running" ]]; then
		return 0
	else
		return 1
	fi
}

check_enabled() {
    local temp=$(is-enabled)
    if [[ "${temp,,}" == "enabled" ]]; then
        return 0
    else
        return 1
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
    logmsg "${color_red}${ICO_MAP[ERR]} Panel is already installed. To install a new or custom version, please uninstall the current panel and $SHELL_SHORT_NAME first.${style_plain}"
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        logmsg "${color_red}${ICO_MAP[ERR]} Please install the panel first${style_plain}"
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
    0)
		logmsg "${color_black}${color_bg_white}${SHELL_SHORT_NAME^^} state:${style_plain} ${color_green}Running${style_plain}"
        show_enable_status
        ;;
    1)
        logmsg "${color_black}${color_bg_white}${SHELL_SHORT_NAME^^} state:${style_plain} ${color_yellow}Not Running${style_plain}"
        show_enable_status
        ;;
    2)
        logmsg "${color_black}${color_bg_white}${SHELL_SHORT_NAME^^} state:${style_plain} ${color_red}Not Installed${style_plain}"
        ;;
    esac
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        logmsg "${color_black}${color_bg_white}Start $SHELL_SHORT_NAME automatically:${style_plain} ${color_green}Yes${style_plain}"
    else
        logmsg "${color_black}${color_bg_white}Start $SHELL_SHORT_NAME automatically:${style_plain} ${color_red}No${style_plain}"
    fi
}

ssl() {
    confirm_options "Do you want to generate a Self-signed Certificate?" "y"
    if [[ $? == 0 ]]; then
        if [[ ! -d $DIR_CERT ]]; then
            mkdir -p $DIR_CERT
        fi
    menu_choice menu_ssl "$1" "Choose certificate type:"
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
                logmsg "${color_red}${ICO_MAP[ERR]} Invalid choice! Return: $schoice${style_plain}"
                return 1
                ;;
        esac
        confirm_options "Please choose DNS" "example.com" "schoice_DNS"  $color_cyan
        cd $DIR_CERT || return
        logmsg "${color_green}${ICO_MAP[INF]} Generating self-signed certificate ($schoice)...${style_plain}"
		openssl req -x509 -nodes -days 3650 -newkey "$key_opt" -keyout "$DIR_CERT/webCertKey.pem" -out "$DIR_CERT/webCert.pem" -subj "/CN=${map_confirm[schoice_DNS]}"
        if [[ $? -eq 0 ]]; then
            chmod -R 600 "$DIR_CERT"
            logmsg "${color_green}${ICO_MAP[INF]} Self-signed certificate generated successfully!${style_plain}"
			echo -e "\n###############################################\n"
			echo -e "                    SSL PATH"
            logmsg "${color_green}${ICO_MAP[INF]} Certificate path: $DIR_CERT/webCert.pem${style_plain}"
            logmsg "${color_green}${ICO_MAP[INF]} Key path: $DIR_CERT/webCertKey.pem${style_plain}"
			echo -e "\n###############################################\n"
			ssl_check
			if [[ $? == 0 ]]; then
				confirm_options "Do you want to check and change the IP address of the panel (RECOMMENDED!)" "y"
				if [[ $? == 0 ]]; then
					exe_set_panel 1
				fi
			fi
        else
            logmsg "${color_red}${ICO_MAP[ERR]} Failed to generate self-signed certificate.${style_plain}"
        fi
    fi
}

check_panel() {
    pgrep -f $NAME_APP > /dev/null
}

is-enabled() {
	if [[ -L "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME" || -f "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME" ]]; then
		echo "enabled"
	fi 
}

db_get() {
    KEY=$1
    TABLE=$2
    sqlite3 $DB "SELECT value FROM $TABLE WHERE key='$KEY';"
}

db_upd() {
    KEY=$1 
    TABLE=$2
    VALUE=$3
    sqlite3 $DB "UPDATE $TABLE SET value='$VALUE' WHERE key='$KEY';"
}

menu_numeric_choice(){
local name_menu=${2:-"$1"}
local cache=$2
menu_numeric_choice_list=""
if [[ -z "$2" ]]; then
    local menu="${!name_menu}"
else
    local menu="$1"
fi
if [[ -f "$DIR_CACHE/menu/$name_menu" && -z $no_cache_needed ]]; then
    source "$DIR_CACHE/menu/$name_menu"
    logmsg "CACHED MENU: $name_menu" nolog
else
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
        if [[ ${menu_arr[$i]} == "[br]" ]]; then
            menu_numeric_choice_list+="${menu_numeric_choice_br_list}"
            max_num_of_choices=$((max_num_of_choices-1))
        else
    menu_numeric_choice_list+="${color_blue}($max_num_of_choices)${style_plain}$([[ $max_num_of_choices -lt 10 ]] && echo "  " || echo " ")[${menu_arr[$i]}]
    "
        fi
    done
    menu_numeric_choice_list+="$menu_numeric_choice_br_list"
    if [[ -z $cache && -z $no_cache_needed ]]; then
        if [[ ! -d "$DIR_CACHE/menu" ]]; then
            mkdir -p "$DIR_CACHE/menu"
        fi
        echo -e "menu_numeric_choice_list=\"$menu_numeric_choice_list\"" >> "$DIR_CACHE/menu/$name_menu"
        echo -e "start_index=\"$start_index\"" >> "$DIR_CACHE/menu/$name_menu"
        echo -e "max_num_of_choices=\"$max_num_of_choices\"" >> "$DIR_CACHE/menu/$name_menu"
    fi
fi
}

declare -A ext_map_zip=( [gzip]=".gz" [bzip2]=".bz2" [xz]=".xz" [zstd]=".zst" [cp]="" )
backup(){
    if [[ ! -d "$DIR_PROJECT/backup/db" ]]; then
        mkdir -p "$DIR_PROJECT/backup/db"
    fi
    now=$(date +"%Y_%m_%d_%H_%M_%S")
    filename="backup_$now.db"
    menu_choice menu_archive "$1" "Choose compression method" "no_compression"
    if ! command -v $schoice >/dev/null 2>&1; then
        confirm_options "Compression tool '$schoice' is not installed. Please install it" "y" "" $color_red
            if [[ $? == 0 ]]; then
                logmsg "Installing compression tool: $schoice"
                opkg update && opkg install "$schoice"
            else
                logmsg "Operation cancelled. Backup not created."
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
                logmsg "${color_red}${ICO_MAP[ERR]} Unsupported compression method${style_plain}"
                return 1
            fi
            ;;
    esac
    local tmpfile=$(ls -1 $DIR_PROJECT/backup/db/$filename* 2>/dev/null)
    if [[ -n $tmpfile ]]; then
        logmsg "${color_green}${ICO_MAP[INF]} Backup created without $schoice: $DIR_PROJECT/backup/db/$filename${style_plain}"
    else
        logmsg "${color_red}${ICO_MAP[ERR]} Failed to create backup!${style_plain}"
    fi
    echo -e "" && logmsg "Available backups:" && echo -e ""
    ls -1 "$DIR_PROJECT/backup/db/"
    echo -e ""
}

delete_old_backups(){
    if [ ! "$(ls -A "$DIR_PROJECT/backup/db")" ]; then
        logmsg "${color_red}${ICO_MAP[ERR]} No backups found.${style_plain}"
    else
        echo -e "" && logmsg "Available backups:" && echo -e ""
        ls -1 "$DIR_PROJECT/backup/db/"
        echo -e ""
        confirm_options "How many recent backups do you want to keep? Please enter a number" "100500" "num_keep"  $color_cyan
        if [[ ${map_confirm[num_keep]} =~ ^[0-9]+$ ]]; then
            ls -1t $DIR_PROJECT/backup/db | tail -n +$((${map_confirm[num_keep]} + 1)) | xargs -I{} rm -- "$DIR_PROJECT/backup/db/{}"
            echo -e "" && logmsg "Available backups:" && echo -e ""
            ls -1 "$DIR_PROJECT/backup/db/"
            echo -e ""
        else
            logmsg "${color_red}${ICO_MAP[ERR]} Invalid number entered!${style_plain}"
        fi	
    fi
}
         
declare -A ext_map_unzip=( [gz]="gzip" [bz2]="bzip2" [xz]="xz" [zst]="zstd" [db]="cp" )
restore(){
    is_files=("$DIR_PROJECT/backup/db"/*)
    is_files=( "${is_files[@]}" )
    if [[ ! -e "${is_files[0]}" ]]; then
        logmsg "No backup files found."
    else
        files=$(ls $DIR_PROJECT/backup/db/)
        menu_choice "$files" "" "Choose which backup to restore" "" "skip"
        selected_file="$schoice"
        fullpath="$DIR_PROJECT/backup/db/$selected_file"
        if [[ -f "$fullpath" ]]; then
            confirm_options "Are you sure you want to restore from $selected_file... this will overwrite current data." "y"
            if [[ $? == 0 ]]; then
                logmsg "${color_yellow}${ICO_MAP[WAR]} Deleting old database file: $DB${style_plain}"
                rm -rf $DB
                ext=${selected_file##*.}
                case ${ext=$?,,} in
                    db)
                        safe_call_command "${ext_map_unzip[$ext]}" "$fullpath" "$DB"
                        ;;
                    *)
                        if [[ -n ${ext_map_unzip[$ext]} ]]; then
                            safe_call_command "${ext_map_unzip[$ext]}" -dc "$fullpath" > "$DB"
                        else
                            logmsg "${color_red}${ICO_MAP[ERR]} Unsupported backup file extension${style_plain}"
                            return 1
                        fi
                        ;;
                esac
                if [[ -f "$DB" ]]; then
                    logmsg "${color_green}${ICO_MAP[INF]} Database restored from $selected_file successfully. Ext: $ext${style_plain}"
                    vacuum && integrity_check 
					confirm_restart
                    logmsg "${color_green}${ICO_MAP[INF]} Restore completed: $DB. Please verify the panel functionality.${style_plain}"
                else
                    logmsg "${color_red}${ICO_MAP[ERR]} Failed to restore database from $selected_file.${style_plain}"
                fi
            else
                logmsg "Restore cancelled."
            fi
        else
            logmsg "${color_red}${ICO_MAP[ERR]} Backup file $selected_file not found! Ext: $ext${style_plain}"
        fi
    fi
}

backup_management(){
    menu_choice menu_backup_management "$1"
    safe_call_function "$schoice"
}

settings(){
    menu_choice menu_settings "$1"
    safe_call_function "$schoice"
}

vacuum(){
    confirm_options "Do you want to perform VACUUM on the database to optimize it" "y"
    if [[ $? == 0 ]]; then
        logmsg "${ICO_MAP[WORK]} Performing VACUUM on database..."
        sqlite3 "$DB" "VACUUM;"
        if [ $? -eq 0 ]; then
            logmsg "${ICO_MAP[GOOD]} Database VACUUM completed successfully."
        else
            logmsg "${ICO_MAP[BAD]} Database VACUUM failed."
        fi
    fi
}

integrity_check(){
    confirm_options "Do you want to perform an integrity check on the database" "y"
    if [[ $? == 0 ]]; then
        logmsg "${ICO_MAP[WORK]} Performing integrity check on database..."
        result=$(sqlite3 "$DB" "PRAGMA integrity_check;")
        if [ "$result" == "ok" ]; then
            logmsg "${ICO_MAP[GOOD]} Database integrity check passed."
        else
            logmsg "${ICO_MAP[BAD]} Database integrity check failed: $result"
        fi
    fi
}

db_management(){
    menu_choice menu_db_management "$1"
    safe_call_function "$schoice"
}

delete_config(){
    if [[ -d "$DIR_CACHE" ]]; then
        logmsg "${ICO_MAP[WORK]} ${color_green}Clearing cache...${style_plain}"
        rm -rf "$DIR_CACHE" 2>/dev/null
		is_files=("$DIR_DB_IN_JSON/"/*)
		is_files=( "${is_files[@]}" )
		if [[ ! -e "${is_files[0]}" ]]; then
			logmsg "Files in $DIR_DB_IN_JSON/ deleted"
		else
            logmsg "Files not found"
        fi
    fi
}

delete_all_json(){
    confirm_options "Do you really want to delete all json files"
    if [[ $? == 0 ]]; then
        delete_config
    fi
}

restore_db_from_json() {
    local count
    count=$(ls -1 "$DIR_DB_IN_JSON"/*.json 2>/dev/null | wc -l)
    if [[ ! $count -ge 7 ]]; then
        logmsg "${ICO_MAP[BAD]} Not enough config json files found in $DIR_DB_IN_JSON/ (found: $count, required >= 7). Restore aborted."
    else
    confirm_options "Do you want to restore config from backup json files" "y"
        if [[ $? == 0 ]]; then
            $0 stop
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
        [ ! -d "$DIR_DB_IN_JSON" ] && { logmsg "${ICO_MAP[BAD]} Directory $DIR_DB_IN_JSON not found"; return 1; }
        logmsg "${ICO_MAP[WORK]} Restoring from $DIR_DB_IN_JSON..."
            ERR=0
            sqlite3 "$DB" "BEGIN;" || ERR=1
            for f in "$DIR_DB_IN_JSON"/*.json; do
                [ -e "$f" ] || continue
                base=$(basename "$f")
                tbl="${base%.json}"
                case "$base" in
                    stats.json|changes.json)
                        logmsg "${ICO_MAP[WORK]} Skipping $base (excluded)"
                        continue
                        ;;
                esac
        logmsg "${ICO_MAP[WORK]} Processing table $tbl..."
        mapfile -t cols < <(sqlite3 -separator '|' "$DB" "PRAGMA table_info(\"$tbl\");" | awk -F'|' '{print $2":"$3}')
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
            [ $ERR -eq 0 ] && logmsg "${ICO_MAP[GOOD]} $tbl restored" || logmsg "${ICO_MAP[BAD]} Restore error for $tbl"
            done
            $0 start
            vacuum && integrity_check
        fi
    fi
}

save_db_to_json() {
    if [[ ! -f "$DB" ]]; then
        logmsg "${ICO_MAP[BAD]} Database file not found: $DB"
        return 1
    fi
    mkdir -p "$DIR_DB_IN_JSON"
    local tables
    tables=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';")
    if [[ -z "$tables" ]]; then
        logmsg "${ICO_MAP[BAD]} No tables found in database. Run: $SHELL_SHORT_NAME install or $NAME_APP migrate"
        return 1
    fi
    local exported=0 skipped=0
    for tbl in $tables; do
        case "$tbl" in
            stats|changes)
                logmsg "${ICO_MAP[WORK]} Skipping $tbl (excluded)"
                skipped=$((skipped+1))
                continue
                ;;
        esac
        local pragma cols select_list=""
        pragma=$(sqlite3 -separator '|' "$DB" "PRAGMA table_info('$tbl');")
        while IFS='|' read -r cid name type notnull dflt pk; do
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
            logmsg "${ICO_MAP[BAD]} Table $tbl has no columns, skipping"
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
        logmsg "${ICO_MAP[GOOD]} Exported: $DIR_DB_IN_JSON/$tbl.json"
        exported=$((exported+1))
    done
    logmsg "${ICO_MAP[WORK]} Build complete. Exported: $exported, skipped: $skipped"
}

permissions(){
	chmod -R 755 $DIR_PROJECT
}

check_all_ruls(){
check_status
if [[ $? != 2 || $1 == 1 ]]; then
    if [[ "$DIR_NOTREAL_CUR" != "$DIR_AUTO_START" ]]; then
        if [[ "$NAME_REAL_SHELL" != "$SHELL_FULL_NAME" ]]; then
            recall=1
            mv "$DIR_REAL_SHELL/$NAME_REAL_SHELL" "$DIR_REAL_SHELL/$SHELL_FULL_NAME"
        fi
        if [[ "$DIR_REAL_SHELL" != "$DIR_PROJECT" ]]; then
            recall=1
            mkdir -p "$DIR_PROJECT"
            mv "$DIR_REAL_SHELL/$SHELL_FULL_NAME" "$DIR_PROJECT/$SHELL_FULL_NAME"
        fi
        if [[ ! -f $DIR_INSTALL_LNK ]]; then
            ln -s $DIR_PROJECT/$SHELL_FULL_NAME $DIR_INSTALL_LNK
            chmod u+x $DIR_INSTALL_LNK
        fi
        if [[ -d "$DIR_PROJECT/repair" && $(ls -A "$DIR_PROJECT/repair" 2>/dev/null) ]]; then
            repair=$(ls -t "$DIR_PROJECT/repair" | head -n 1)
            rm -f "$DIR_AUTO_START/$repair"
            ln -s "$DIR_PROJECT/$SHELL_FULL_NAME" "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME"
            rm -rf "$DIR_PROJECT/repair"
        bash $DIR_PROJECT/$SHELL_FULL_NAME "$COMMANDS_CALL"
        fi
    else
        if [[ "$DIR_AUTO_START/$PRIORITY$SHELL_SHORT_NAME" != "$DIR_NOTREAL_CUR/$NAME_NOTREAL_SHELL" ]]; then
            if [[ ! -d "$DIR_PROJECT/repair" ]]; then
                mkdir -p "$DIR_PROJECT/repair"
            fi
            cp "$DIR_NOTREAL_CUR/$NAME_NOTREAL_SHELL" "$DIR_PROJECT/repair/"
        fi
        recall=1
    fi

    if [[ $recall -gt 0 ]]; then
        permissions
        bash $DIR_REAL_SHELL/$NAME_REAL_SHELL "$COMMANDS_CALL"
    fi
fi
}

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
bye(){
    logmsg "${color_yellow}Bye...${style_plain}"
    echo -e "" && exit 0
}

before_show_main_menu() {
	echo -e "" && echo -n -e "${color_yellow}\u2190 Press enter to return to the main menu${style_plain}" && read temp
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

speedtest() {
	confirm_options "Do you want to run a speed test for $SHELL_SHORT_NAME" "y"
	if [[ $? == 0 ]]; then
		logmsg "${ICO_MAP[WORK]} Running speed test..."
		safe_call_command iperf3 -Vc speedtest.serverius.net -p 5002
		logmsg "${ICO_MAP[INF]} Speed test completed."
	fi
}

update_geo() {

    menu_choice menu_update_geo_list "$1" "Choose certificate type:"
    
    cd "$DIR_PROJECT/bin/" || return
	if [[ -n $schoice ]]; then
		stop
	fi
    case ${schoice=$?,,} in
    loyalsoldier)
        rm -f geoip.dat geosite.dat
        wget -N https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
        wget -N https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
        echo -e "${green}Loyalsoldier datasets have been updated successfully!${plain}"
        ;;
    chocolate4u)
        rm -f geoip_IR.dat geosite_IR.dat
        wget -O geoip_IR.dat -N https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geoip.dat
        wget -O geosite_IR.dat -N https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geosite.dat
        echo -e "${green}chocolate4u datasets have been updated successfully!${plain}"
        ;;
    runetfreedom)
        rm -f geoip_RU.dat geosite_RU.dat
        wget -O geoip_RU.dat -N https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat
        wget -O geosite_RU.dat -N https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat
        echo -e "${green}runetfreedom datasets have been updated successfully!${plain}"
        ;;
    esac
	if [[ -n $schoice ]]; then
		confirm_restart
	fi
}

repair(){
    confirm_options "Do you really want to repair $SHELL_SHORT_NAME installation?" "n"
    if [[ $? == 0 ]]; then
		logmsg "${ICO_MAP[WORK]} Repairing $SHELL_SHORT_NAME installation..."
        permissions && check_all_ruls 1 && migration && vacuum && integrity_check
		logmsg "${ICO_MAP[INF]} Repairing completed."
		confirm_restart
    fi
}

menu_exit="${color_magenta}Exit${style_plain}
[br]
"
menu_install="
Install $SHELL_SHORT_NAME ${color_green}(latest version recommended:$RECCOMMENDED_VERSION)${style_plain}
Custom $SHELL_SHORT_NAME version Install ${color_yellow}(Not recommended)${style_plain}
"
menu_extra="Update Check
Uninstall $SHELL_SHORT_NAME Panel
Install_Custom $NAME_APP/script version  ${color_yellow}(Not recommended)${style_plain}
[br]
Settings Management
Log Check $SHELL_SHORT_NAME
[br]
Reset_admin credentials to default
Set_admin credentials
Reset_Panel Settings
Set_Panel settings
View_Panel Settings
[br]
SSL Self-signed Certificate Generation
[br]
Start $SHELL_SHORT_NAME
Stop $SHELL_SHORT_NAME
Restart $SHELL_SHORT_NAME
Status Check $SHELL_SHORT_NAME
[br]
Enable Autostart $SHELL_SHORT_NAME
Disable Autostart $SHELL_SHORT_NAME
"
menu_install_custom="
${color_magenta}Show_main_menu${style_plain}
[br]
Install_custom_$NAME_APP script version  ${color_yellow}(Not recommended)${style_plain}
Install_custom_script version  ${color_yellow}(Not recommended)${style_plain}
"
menu_update="
${color_magenta}Show_main_menu${style_plain}
[br]
Update_all
Update_script only
Update_panel only
"
menu_settings="
${color_magenta}Show_main_menu${style_plain}
[br]
Backup_management
Update_geo files
Speedtest your internet connection
Edit_settings file manually
DB_management
Clear_all_cache files
Repair $SHELL_SHORT_NAME installation
"
menu_db_management="
${color_magenta}Show_main_menu${style_plain}
[br]
Save_db_to_json files
Restore_db_from_json files ${color_red}(Careful!)${style_plain}
Delete_all_json files
[br]
Vacuum Performing on DB
Integrity_check performing on DB
"
menu_backup_management="
${color_magenta}Show_main_menu${style_plain}
[br]
Backup DB panel settings
Restore DB panel settings
Delete_old_backups
"
menu_archive="
ZSTD maximum compression, fast ${color_green}(recommended)${style_plain}
GZIP low compression, fast
BZIP2 stronger compression, but slower
XZ maximum compression, takes longer
CP it means no compression, very fast
"
menu_ssl="
Ed25519 ${color_green}(*recommended*)${style_plain}
RSA_2048
RSA_4096
ECDSA_prime256v1
ECDSA_secp384r1
"
menu_update_geo_list="
Loyalsoldier datasets (geoip.dat, geosite.dat)
chocolate4u datasets (geoip_IR.dat, geosite_IR.dat)
runetfreedom datasets (geoip_RU.dat, geosite_RU.dat)
"
if check_status 2>/dev/null; [[ ! $? -eq 2 ]]; then
    version_panel
fi

show_main_menu() {
schoice=""
if [[ $# -gt 0 ]]; then
	call=$1
else
    if [[ -d "$DIR_PROJECT/new" ]]; then
        check_all_ruls && dos2unix "$DIR_REAL_SHELL/$NAME_REAL_SHELL"
        confirm_options "Do you want to start $SHELL_SHORT_NAME and enable autostart" "y"
        if [[ $? == 0 ]]; then
            start && enable
        fi
        rm -rf "$DIR_PROJECT/new"
    fi
	commands_arg=$2
echo -e "${style_new_line}${color_red}
 _____ __   __        _    _   _ 
|____ |\ \ / /       | |  | | (_)
    / / \ V /  ____  | |  | |  _ 
    \ \ / _ \ |____| | |  | | | |
____/ // / \ \       | |__| | | |
\____/ \/   \/        \____/  |_|
${style_plain}
"
    echo -e "${color_yellow}${SHELL_SHORT_NAME^^} Script:     ${color_white}${CURRENT_VERSION_SCRIPT}${style_plain}"
	show_main_menu=$menu_exit
    if [[ -f $DIR_PROJECT/$NAME_APP ]]; then
        echo -e "${SHELL_SHORT_NAME^^} Panel:      $CURRENT_VERSION_ALL" && show_main_menu+=$menu_extra && echo -e "" && show_status && echo -e ""
	else
        show_main_menu+=$menu_install
    fi
    menu_choice show_main_menu "$schoice"
    call=$schoice
fi
logmsg "Choice: $call" nolog
	case ${call,,} in
        exit)
            bye
        ;;
        install)
            check_uninstall && safe_call_function "$call" $NAME_APP "$RECCOMMENDED_VERSION"
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
# AUTO_START ------------------------------------------------------------
if [[ "$DIR_NOTREAL_CUR" == "$DIR_AUTO_START" ]]; then
    logmsg "Auto start script initialized" nolog
	PROCS=$NAME_APP
    ENABLED=yes
    ARGS=""
    PREARGS=""
    DESC=$PROCS
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
                echo -e "  Commands: ${color_green}start${style_plain} | ${color_red}stop${style_plain} | ${color_yellow}restart${style_plain} | status"
                ;;
        esac
    logmsg "Auto start script ended" nolog
    exit 1
else
    [[ $EUID -ne 0 ]] && logmsg "${color_red}Fatal error: ${style_plain} Please run this script with root privilege \n " && exit 1
    if [[ $# -gt 0 ]]; then
    COMMANDS_CALL=$1 && commands_arg=$2
        if check_status 2>/dev/null; [[ $? -eq 2 ]]; then
            show_main_menu "$COMMANDS_CALL" "$commands_arg"
        elif check_status 2>/dev/null; [[ ! $? -eq 2 ]]; then
            check_install && safe_call_function "$@"
        else
            logmsg "${color_red}${ICO_MAP[ERR]} First install the panel! ${style_plain}" && bye
        fi
    else
        show_main_menu
    fi
    check_show_main_menu
fi
# AUTO_END ------------------------------------------------------------