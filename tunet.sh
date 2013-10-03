#!/bin/bash

readonly protocol="http"
readonly host="net.tsinghua.edu.cn"
verbose=false

check_network() {
	wireness=`curl -I $host 2>/dev/null | sed -n 's/^Location: *\(.*\)\/.*$/\1/p'`
	if [[ -z "$wireness" ]]; then
		echo "Network connection failed." >&2
		return 1
	fi
	echo "Connected to $wireness network." >&2
}

http_request() {
	local args=(
		"-H \"Origin:$protocol://$host\""
	)
	if [[ -n "$wireness" ]]; then
		args+=("-H \"Referer:$protocol://$host/$wireness/\"")
	fi
	if [[ -n "$agent" ]]; then
		args+=("-A \"$agent\"")
	fi
	local path=$1
	local url="$protocol://$host$path"
	local request="curl ${args[@]} ${@:2}"
	if $verbose; then
		request+=" -vs \"$url\""
		echo $request >&2
	else
		request+=" -s \"$url\" 2>/dev/null"
	fi
	local response=`eval $request`
	if $verbose; then
		echo "Response data: [$response]" >&2
	fi
	echo "$response"
}

check_online() {
	local online=`http_request /cgi-bin/do_login -d \"action=check_online\"`
	[[ -n "$online" ]] && (echo "已登录清华大学校园网。"; display_online_status "$online")
}

get_status() {
	check_online || echo "您不在线上。"
}

get_user_account() {
	printf "请输入用户名："
	read user
	printf "请输入密码："
	read -s password
	password=`printf "$password" | md5sum | awk '{print $1}'`
	echo
}

log_in() {
	echo "** 登录清华大学校园网 **"
	if [[ -z "$user" ]] || [[ -z "$password" ]]; then
		get_user_account
	fi
	local data="username=$user&password=$password&drop=0&type=1&n=100"
	local response=`http_request /cgi-bin/do_login -d \"$data\"`
	if [[ "$response" =~ ^[0-9]+, ]]; then
		response=(${response//,/ })
		echo "登录成功。"
		echo "用户名： $user"
		echo "已用流量：" `traffic ${response[2]}`
		return 0
	else
		display_login_error $response
		return 1
	fi
}

log_out() {
	local response=`http_request /cgi-bin/do_logout -d \"\"`
	display_logout_result $response
	[[ -n "$response" ]]
}

display_login_error() {
	local username_error="用户名错误。"
	local password_error="密码错误。"
	local user_tab_error="认证程序未启动。"
	local user_group_error="您的计费组信息不正确。"
	local non_auth_error="您无须认证，可直接上网。"
	local status_error="用户已欠费，请尽快充值。"
	local available_error="您的帐号已停用。"
	local delete_error="您的帐号已删除。"
	local ip_exist_error="IP已存在，请稍后再试。"
	local usernum_error="用户数已达上限。"
	local online_num_error="该帐号的登录人数已超过限额。请登录\`https://usereg.tsinghua.edu.cn'断开不用的连接。"
	local mode_error="系统已禁止Web方式登录，请使用客户端。"
	local time_policy_error="当前时段不允许连接。"
	local flux_error="您的流量已超支。"
	local minutes_error="您的时长已超支。"
	local ip_error="您的IP地址不合法。"
	local mac_error="您的MAC地址不合法。"
	local sync_error="您的资料已修改，正在等待同步，请2分钟后再试。"
	local ip_alloc="您不是这个地址的合法拥有者，IP地址已经分配给其它用户。"
	local ip_invaild="您是区内地址，无法使用。"

	local code=$1
	local message=""
	if [[ "$code" =~ ^password_error@[0-9]+ ]]; then
		message="密码错误或会话失效。"
		message+=" [`date -d @${code:15} "+%x %T"`]"
	else
		message=${!code}
	fi
	if [[ -z "$message" ]]; then
		message="未知错误。"
	fi
	echo $message
}

display_logout_result() {
	local logout_ok="连接已断开。"
	local not_online_error="您不在线上。"

	local message=${!1}
	if [[ -z "$message" ]]; then
		message="操作失败。"
	fi
	echo $message
}

display_online_status() {
	local data=$1
	local array=(${data//,/ })
	echo "用户名：" ${array[1]}
	echo "连接时长：" `time_elapsed ${array[4]}`
	echo "已用流量：" `traffic ${array[2]}`
}

time_elapsed() {
	date -d "@$1" -u +%T
}

traffic() {
	echo "$1" | awk '
		function format(bytes, base) {
			type[base ** 3] = "GB";
			type[base ** 2] = "MB";
			type[base] = "kB";
			for (x = base ** 3; x >= base; x /= base) {
				if (bytes >= x) {
					printf("%.2f %s", bytes / x, type[x]);
					return;
				}
			}
			printf("%d B", bytes);
		}
		{ format($1, 1000); }
	'
}

usage() {
	echo "TUNet Shell"
	echo "Usage: tunet [OPTION] COMMAND"
	echo
	echo "Available commands:"
	echo "  login    Log in"
	echo "  logout   Log out"
	echo "  network  Check network condition"
	echo "  status   Show user status"
	echo
	echo "Options:"
	echo "  -u FILE  Load user configuration file"
	echo "  -h       Print this help message and exit"
	echo "  -v       Explain what is being done verbosely"
}

if [[ $# == 0 ]]; then
	usage; exit 0
fi

while getopts ":u:hv" opt; do
	case $opt in
		u) source $OPTARG || exit;;
		h) usage; exit 0;;
		v) verbose=true;;
		\?) echo "Invalid option: \`-$OPTARG'" >&2; exit 1;;
		:) echo "Option \`-$OPTARG' requires an argument." >&2; exit 1;;
	esac
done

if [[ -n "${@:$OPTIND+1}" ]]; then
	echo "Too many commands are specified." >&2; exit 1
fi

cmd=${@:$OPTIND}
if [[ -z "$cmd" ]]; then
	echo "Please specify a command." >&2; exit 1
fi
case $cmd in
	network) check_network; exit;;
	login) check_network && (check_online || log_in); exit;;
	logout) check_network && log_out; exit;;
	status) check_network && get_status; exit;;
	*) echo "Invalid command \`$cmd'." >&2; exit 1;;
esac
