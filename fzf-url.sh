#!/usr/bin/env bash
#===============================================================================
#   Original Author: Wenxuan
#    Original Email: wenxuangm@gmail.com
#  Created: 2018-04-06 12:12
#
#   Updated By: Kenan Pelit
#    Email: kenanpelit@gmail.com
#   Update: 2025-04-07 - NixOS ve Zen Browser desteği eklendi
#===============================================================================
get_fzf_options() {
	local fzf_options
	local fzf_default_options='-w 100% -h 50% --multi -0 --no-preview'
	fzf_options="$(tmux show -gqv '@fzf-url-fzf-options')"
	[ -n "$fzf_options" ] && echo "$fzf_options" || echo "$fzf_default_options"
}

fzf_filter() {
	eval "fzf-tmux $(get_fzf_options)"
}

LOG_FILE="${TMUX_FZF_URL_LOG_FILE:-/tmp/tmux-fzf-url-debug.log}"
log() {
	printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"
}

get_tmux_browser() {
	local line
	line="$(tmux show-environment -g BROWSER 2>/dev/null || true)"
	case "$line" in
		BROWSER=*) printf '%s\n' "${line#BROWSER=}" ;;
		*) printf '%s\n' "" ;;
	esac
}

pick_browser_cmd() {
	local browser_value="$1"
	local IFS=':'
	local candidate

	for candidate in $browser_value; do
		candidate="${candidate#"${candidate%%[![:space:]]*}"}"
		candidate="${candidate%"${candidate##*[![:space:]]}"}"
		[ -z "$candidate" ] && continue

		if command -v "${candidate%% *}" >/dev/null 2>&1; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done

	return 1
}

run_open_cmd() {
	local cmd="$1"
	local url="$2"

	[ -z "$cmd" ] && return 1

	# Keep URL in positional arg for safe quoting, allow command with extra flags.
	sh -c "$cmd \"\$1\" >/dev/null 2>&1" sh "$url"
}

open_url() {
	local url="$1"
	local browser_value=""
	local browser_cmd=""

	log "opening URL: $url"

	if run_open_cmd "$custom_open" "$url"; then
		log "opened with custom command: $custom_open"
		return 0
	fi

	browser_value="$(get_tmux_browser)"
	[ -z "$browser_value" ] && browser_value="${BROWSER:-}"
	browser_cmd="$(pick_browser_cmd "$browser_value" 2>/dev/null || true)"

	if [ -n "$browser_cmd" ] && run_open_cmd "$browser_cmd" "$url"; then
		log "opened with BROWSER command: $browser_cmd"
		return 0
	fi

	if run_open_cmd "xdg-open" "$url"; then
		log "opened with xdg-open"
		return 0
	fi

	if run_open_cmd "gio open" "$url"; then
		log "opened with gio open"
		return 0
	fi

	if run_open_cmd "open" "$url"; then
		log "opened with open (macOS)"
		return 0
	fi

	tmux display-message "tmux-fzf-url: opener bulunamadi (@fzf-url-open/BROWSER/xdg-open)"
	log "failed: no usable opener found"
	return 1
}

custom_open="${3:-}"
log "script started, custom_open='$custom_open'"

limit='screen'
[[ $# -ge 2 ]] && limit=$2
if [[ $limit == 'screen' ]]; then
	content="$(tmux capture-pane -J -p -e)"
else
	content="$(tmux capture-pane -J -p -e -S -"$limit")"
fi

# URL'leri topla
urls=$(echo "$content" | grep -oE '(https?|ftp|file):/?//[-A-Za-z0-9+&@#/%?=~_|!:,.;]*[-A-Za-z0-9+&@#/%=~_|]')
wwws=$(echo "$content" | grep -oE '(http?s://)?www\.[a-zA-Z](-?[a-zA-Z0-9])+\.[a-zA-Z]{2,}(/\S+)*' | grep -vE '^https?://' | sed 's/^\(.*\)$/http:\/\/\1/')
ips=$(echo "$content" | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(:[0-9]{1,5})?(/\S+)*' | sed 's/^\(.*\)$/http:\/\/\1/')
gits=$(echo "$content" | grep -oE '(ssh://)?git@\S*' | sed 's/:/\//g' | sed 's/^\(ssh\/\/\/\)\{0,1\}git@\(.*\)$/https:\/\/\2/')
gh=$(echo "$content" | grep -oE "['\"]([_A-Za-z0-9-]*/[_.A-Za-z0-9-]*)['\"]" | sed "s/['\"]//g" | sed 's#.#https://github.com/&#')

if [[ $# -ge 1 && "$1" != '' ]]; then
	extras=$(echo "$content" | eval "$1")
fi

items=$(
	printf '%s\n' "${urls[@]}" "${wwws[@]}" "${gh[@]}" "${ips[@]}" "${gits[@]}" "${extras[@]}" |
		grep -v '^$' |
		sort -u |
		nl -w3 -s '  '
)

[ -z "$items" ] && tmux display 'tmux-fzf-url: no URLs found' && exit

log "found URLs: $(echo "$items" | wc -l)"

fzf_filter <<<"$items" | awk '{print $2}' |
	while read -r chosen; do
		log "selected URL: $chosen"
		open_url "$chosen"
	done
