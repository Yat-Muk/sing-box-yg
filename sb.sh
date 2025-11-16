#!/bin/bash
export LANG=en_US.UTF-8
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;36m'
bblue='\033[0;34m'
plain='\033[0m'
red(){ echo -e "\033[31m\033[01m$1\033[0m";}
green(){ echo -e "\033[32m\033[01m$1\033[0m";}
yellow(){ echo -e "\033[33m\033[01m$1\033[0m";}
blue(){ echo -e "\033[36m\033[01m$1\033[0m";}
white(){ echo -e "\033[37m\033[01m$1\033[0m";}
readp(){ read -p "$(yellow "$1")" $2;}
[[ $EUID -ne 0 ]] && yellow "請以root模式運行腳本" && exit
#[[ -e /etc/hosts ]] && grep -qE '^ *172.65.251.78 gitlab.com' /etc/hosts || echo -e '\n172.65.251.78 gitlab.com' >> /etc/hosts
if [[ -f /etc/redhat-release ]]; then
release="Centos"
elif cat /etc/issue | grep -q -E -i "alpine"; then
release="alpine"
elif cat /etc/issue | grep -q -E -i "debian"; then
release="Debian"
elif cat /etc/issue | grep -q -E -i "ubuntu"; then
release="Ubuntu"
elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
release="Centos"
elif cat /proc/version | grep -q -E -i "debian"; then
release="Debian"
elif cat /proc/version | grep -q -E -i "ubuntu"; then
release="Ubuntu"
elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
release="Centos"
else 
red "腳本不支持當前的系統，請選擇使用Ubuntu,Debian,Centos系統。" && exit
fi
export sbfiles="/etc/s-box/sb10.json /etc/s-box/sb11.json /etc/s-box/sb.json"
export sbnh=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}' | cut -d '.' -f 1,2)
vsid=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)
op=$(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | grep -i pretty_name | cut -d \" -f2)
#if [[ $(echo "$op" | grep -i -E "arch|alpine") ]]; then
if [[ $(echo "$op" | grep -i -E "arch") ]]; then
red "腳本不支持當前的 $op 系統，請選擇使用Ubuntu,Debian,Centos系統。" && exit
fi
version=$(uname -r | cut -d "-" -f1)
[[ -z $(systemd-detect-virt 2>/dev/null) ]] && vi=$(virt-what 2>/dev/null) || vi=$(systemd-detect-virt 2>/dev/null)
case $(uname -m) in
armv7l) cpu=armv7;;
aarch64) cpu=arm64;;
x86_64) cpu=amd64;;
*) red "目前腳本不支持$(uname -m)架構" && exit;;
esac
#bit=$(uname -m)
#if [[ $bit = "aarch64" ]]; then
#cpu="arm64"
#elif [[ $bit = "x86_64" ]]; then
#amdv=$(cat /proc/cpuinfo | grep flags | head -n 1 | cut -d: -f2)
#[[ $amdv == *avx2* && $amdv == *f16c* ]] && cpu="amd64v3" || cpu="amd64"
#else
#red "目前腳本不支持 $bit 架構" && exit
#fi
if [[ -n $(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk -F ' ' '{print $3}') ]]; then
bbr=`sysctl net.ipv4.tcp_congestion_control | awk -F ' ' '{print $3}'`
elif [[ -n $(ping 10.0.0.2 -c 2 | grep ttl) ]]; then
bbr="Openvz版bbr-plus"
else
bbr="Openvz/Lxc"
fi
hostname=$(hostname)

if [ ! -f sbyg_update ]; then
green "首次安裝Sing-box-yg腳本必要的依賴……"
if [[ x"${release}" == x"alpine" ]]; then
apk update
apk add jq openssl iproute2 iputils coreutils expect git socat iptables grep util-linux dcron tar tzdata 
apk add virt-what
else
if [[ $release = Centos && ${vsid} =~ 8 ]]; then
cd /etc/yum.repos.d/ && mkdir backup && mv *repo backup/ 
curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-8.repo
sed -i -e "s|mirrors.cloud.aliyuncs.com|mirrors.aliyun.com|g " /etc/yum.repos.d/CentOS-*
sed -i -e "s|releasever|releasever-stream|g" /etc/yum.repos.d/CentOS-*
yum clean all && yum makecache
cd
fi
if [ -x "$(command -v apt-get)" ]; then
apt update -y
apt install jq cron socat iptables-persistent coreutils util-linux -y
elif [ -x "$(command -v yum)" ]; then
yum update -y && yum install epel-release -y
yum install jq socat coreutils util-linux -y
elif [ -x "$(command -v dnf)" ]; then
dnf update -y
dnf install jq socat coreutils util-linux -y
fi
if [ -x "$(command -v yum)" ] || [ -x "$(command -v dnf)" ]; then
if [ -x "$(command -v yum)" ]; then
yum install -y cronie iptables-services
elif [ -x "$(command -v dnf)" ]; then
dnf install -y cronie iptables-services
fi
systemctl enable iptables >/dev/null 2>&1
systemctl start iptables >/dev/null 2>&1
fi
if [[ -z $vi ]]; then
apt install iputils-ping iproute2 systemctl -y
fi

packages=("curl" "openssl" "iptables" "tar" "expect" "wget" "xxd" "python3" "qrencode" "git")
inspackages=("curl" "openssl" "iptables" "tar" "expect" "wget" "xxd" "python3" "qrencode" "git")
for i in "${!packages[@]}"; do
package="${packages[$i]}"
inspackage="${inspackages[$i]}"
if ! command -v "$package" &> /dev/null; then
if [ -x "$(command -v apt-get)" ]; then
apt-get install -y "$inspackage"
elif [ -x "$(command -v yum)" ]; then
yum install -y "$inspackage"
elif [ -x "$(command -v dnf)" ]; then
dnf install -y "$inspackage"
fi
fi
done
fi
touch sbyg_update
fi

if [[ $vi = openvz ]]; then
TUN=$(cat /dev/net/tun 2>&1)
if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then 
red "檢測到未開啓TUN，現嘗試添加TUN支持" && sleep 4
cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun
TUN=$(cat /dev/net/tun 2>&1)
if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '處於錯誤狀態' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then 
green "添加TUN支持失敗，建議與VPS廠商溝通或後台設置開啓" && exit
else
echo '#!/bin/bash' > /root/tun.sh && echo 'cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun' >> /root/tun.sh && chmod +x /root/tun.sh
grep -qE "^ *@reboot root bash /root/tun.sh >/dev/null 2>&1" /etc/crontab || echo "@reboot root bash /root/tun.sh >/dev/null 2>&1" >> /etc/crontab
green "TUN守護功能已啓動"
fi
fi
fi

v4v6(){
    export v4=$(curl -s4m5 icanhazip.com -k)
    export v6=$(curl -s6m5 icanhazip.com -k)
}

warpcheck(){
wgcfv6=$(curl -s6m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
wgcfv4=$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
}

v6(){
v4orv6(){
if [ -z "$(curl -s4m5 icanhazip.com -k)" ]; then
echo
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
yellow "檢測到 純IPV6 VPS，添加NAT64"
echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1" > /etc/resolv.conf
endip=2606:4700:d0::a29f:c101
ipv=prefer_ipv6
else
endip=162.159.192.1
ipv=prefer_ipv4
fi
if [ -n "$(curl -s6m5 icanhazip.com -k)" ]; then
endip=2606:4700:d0::a29f:c001
else
endip=162.159.192.1
fi
}
warpcheck
if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
v4orv6
else
systemctl stop wg-quick@wgcf >/dev/null 2>&1
kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
v4orv6
systemctl start wg-quick@wgcf >/dev/null 2>&1
systemctl restart warp-go >/dev/null 2>&1
systemctl enable warp-go >/dev/null 2>&1
systemctl start warp-go >/dev/null 2>&1
fi
}

argopid(){
ym=$(cat /etc/s-box/sbargoympid.log 2>/dev/null)
ls=$(cat /etc/s-box/sbargopid.log 2>/dev/null)
}

close(){
systemctl stop firewalld.service >/dev/null 2>&1
systemctl disable firewalld.service >/dev/null 2>&1
setenforce 0 >/dev/null 2>&1
ufw disable >/dev/null 2>&1
iptables -P INPUT ACCEPT >/dev/null 2>&1
iptables -P FORWARD ACCEPT >/dev/null 2>&1
iptables -P OUTPUT ACCEPT >/dev/null 2>&1
iptables -t mangle -F >/dev/null 2>&1
iptables -F >/dev/null 2>&1
iptables -X >/dev/null 2>&1
netfilter-persistent save >/dev/null 2>&1
if [[ -n $(apachectl -v 2>/dev/null) ]]; then
systemctl stop httpd.service >/dev/null 2>&1
systemctl disable httpd.service >/dev/null 2>&1
service apache2 stop >/dev/null 2>&1
systemctl disable apache2 >/dev/null 2>&1
fi
sleep 1
green "執行開放端口，關閉防火牆完畢"
}

openyn(){
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
readp "是否開放端口，關閉防火牆？\n1、是，執行 (回車默認)\n2、否，跳過！自行處理\n請選擇【1-2】：" action
if [[ -z $action ]] || [[ "$action" = "1" ]]; then
close
elif [[ "$action" = "2" ]]; then
echo
else
red "輸入錯誤,請重新選擇" && openyn
fi
}

inssb(){
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "使用哪個內核版本？目前：1.10系列正式版內核支持geosite分流，1.10系列之後最新內核不支持geosite分流"
yellow "1：使用1.10系列之後最新正式版內核 (回車默認)"
yellow "2：使用1.10.7正式版內核"
readp "請選擇【1-2】：" menu
if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
sbcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]+",' | sed -n 1p | tr -d '",')
#sbcore="1.12.5"
else
sbcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"1\.10[0-9\.]*",'  | sed -n 1p | tr -d '",')
fi
sbname="sing-box-$sbcore-linux-$cpu"
curl -L -o /etc/s-box/sing-box.tar.gz  -# --retry 2 https://github.com/SagerNet/sing-box/releases/download/v$sbcore/$sbname.tar.gz
if [[ -f '/etc/s-box/sing-box.tar.gz' ]]; then
tar xzf /etc/s-box/sing-box.tar.gz -C /etc/s-box
mv /etc/s-box/$sbname/sing-box /etc/s-box
rm -rf /etc/s-box/{sing-box.tar.gz,$sbname}
if [[ -f '/etc/s-box/sing-box' ]]; then
chown root:root /etc/s-box/sing-box
chmod +x /etc/s-box/sing-box
blue "成功安裝 Sing-box 內核版本：$(/etc/s-box/sing-box version | awk '/version/{print $NF}')"
else
red "下載 Sing-box 內核不完整，安裝失敗，請再運行安裝一次" && exit
fi
else
red "下載 Sing-box 內核失敗，請再運行安裝一次，並檢測VPS的網絡是否可以訪問Github" && exit
fi
}

inscertificate(){
ymzs(){
ym_vl_re=www.apple.com
echo
blue "Vless-reality的SNI域名默認為 www.apple.com"
blue "Vmess-ws將開啓TLS，Hysteria-2、Tuic-v5將使用 $(cat /root/ygkkkca/ca.log 2>/dev/null) 證書，並開啓SNI證書驗證"
tlsyn=true
ym_vm_ws=$(cat /root/ygkkkca/ca.log 2>/dev/null)
certificatec_vmess_ws='/root/ygkkkca/cert.crt'
certificatep_vmess_ws='/root/ygkkkca/private.key'
certificatec_hy2='/root/ygkkkca/cert.crt'
certificatep_hy2='/root/ygkkkca/private.key'
certificatec_tuic='/root/ygkkkca/cert.crt'
certificatep_tuic='/root/ygkkkca/private.key'
}

zqzs(){
ym_vl_re=www.apple.com
echo
blue "Vless-reality的SNI域名默認為 www.apple.com"
blue "Vmess-ws將關閉TLS，Hysteria-2、Tuic-v5將使用bing自簽證書，並關閉SNI證書驗證"
tlsyn=false
ym_vm_ws=www.bing.com
certificatec_vmess_ws='/etc/s-box/cert.pem'
certificatep_vmess_ws='/etc/s-box/private.key'
certificatec_hy2='/etc/s-box/cert.pem'
certificatep_hy2='/etc/s-box/private.key'
certificatec_tuic='/etc/s-box/cert.pem'
certificatep_tuic='/etc/s-box/private.key'
}

red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "二、生成並設置相關證書"
echo
blue "自動生成bing自簽證書中……" && sleep 2
openssl ecparam -genkey -name prime256v1 -out /etc/s-box/private.key
openssl req -new -x509 -days 36500 -key /etc/s-box/private.key -out /etc/s-box/cert.pem -subj "/CN=www.bing.com"
echo
if [[ -f /etc/s-box/cert.pem ]]; then
blue "生成bing自簽證書成功"
else
red "生成bing自簽證書失敗" && exit
fi
echo
if [[ -f /root/ygkkkca/cert.crt && -f /root/ygkkkca/private.key && -s /root/ygkkkca/cert.crt && -s /root/ygkkkca/private.key ]]; then
yellow "經檢測，之前已使用Acme-yg腳本申請過Acme域名證書：$(cat /root/ygkkkca/ca.log) "
green "是否使用 $(cat /root/ygkkkca/ca.log) 域名證書？"
yellow "1：否！使用自簽的證書 (回車默認)"
yellow "2：是！使用 $(cat /root/ygkkkca/ca.log) 域名證書"
readp "請選擇【1-2】：" menu
if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
zqzs
else
ymzs
fi
else
green "如果你有解析完成的域名，是否申請一個Acme域名證書？"
yellow "1：否！繼續使用自簽的證書 (回車默認)"
yellow "2：是！使用Acme-yg腳本申請Acme證書 (支持常規80端口模式與Dns API模式)"
readp "請選擇【1-2】：" menu
if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
zqzs
else
bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)
if [[ ! -f /root/ygkkkca/cert.crt && ! -f /root/ygkkkca/private.key && ! -s /root/ygkkkca/cert.crt && ! -s /root/ygkkkca/private.key ]]; then
red "Acme證書申請失敗，繼續使用自簽證書" 
zqzs
else
ymzs
fi
fi
fi
}

chooseport(){
if [[ -z $port ]]; then
port=$(shuf -i 10000-65535 -n 1)
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被佔用，請重新輸入端口" && readp "自定義端口:" port
done
else
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被佔用，請重新輸入端口" && readp "自定義端口:" port
done
fi
blue "確認的端口：$port" && sleep 2
}

vlport(){
readp "\n設置Vless-reality端口[1-65535] (回車跳過為10000-65535之間的隨機端口)：" port
chooseport
port_vl_re=$port
}
vmport(){
readp "\n設置Vmess-ws端口[1-65535] (回車跳過為10000-65535之間的隨機端口)：" port
chooseport
port_vm_ws=$port
}
hy2port(){
readp "\n設置Hysteria2主端口[1-65535] (回車跳過為10000-65535之間的隨機端口)：" port
chooseport
port_hy2=$port
}
tu5port(){
readp "\n設置Tuic5主端口[1-65535] (回車跳過為10000-65535之間的隨機端口)：" port
chooseport
port_tu=$port
}
anytlsport(){
readp "\n設置AnyTLS主端口[1-65535] (回車跳過為10000-65535之間的隨機端口)：" port
chooseport
port_anytls=$port
}

insport(){
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "三、設置各個協議端口"
yellow "1：自動生成每個協議的隨機端口 (10000-65535範圍內)，回車默認"
yellow "2：自定義每個協議端口"
readp "請輸入【1-2】：" port
if [ -z "$port" ] || [ "$port" = "1" ] ; then
ports=()
for i in {1..5}; do
while true; do
port=$(shuf -i 10000-65535 -n 1)
if ! [[ " ${ports[@]} " =~ " $port " ]] && \
[[ -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && \
[[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
ports+=($port)
break
fi
done
done
port_vm_ws=${ports[0]}
port_vl_re=${ports[1]}
port_hy2=${ports[2]}
port_tu=${ports[3]}
port_anytls=${ports[4]}
if [[ $tlsyn == "true" ]]; then
numbers=("2053" "2083" "2087" "2096" "8443")
else
numbers=("8080" "8880" "2052" "2082" "2086" "2095")
fi
port_vm_ws=${numbers[$RANDOM % ${#numbers[@]}]}
until [[ -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port_vm_ws") ]]
do
if [[ $tlsyn == "true" ]]; then
numbers=("2053" "2083" "2087" "2096" "8443")
else
numbers=("8080" "8880" "2052" "2082" "2086" "2095")
fi
port_vm_ws=${numbers[$RANDOM % ${#numbers[@]}]}
done
echo
blue "根據Vmess-ws協議是否啓用TLS，隨機指定支持CDN優選IP的標準端口：$port_vm_ws"
else
vlport && vmport && hy2port && tu5port && anytlsport
fi
echo
blue "各協議端口確認如下"
blue "Vless-reality端口：$port_vl_re"
blue "Vmess-ws端口：$port_vm_ws"
blue "Hysteria-2端口：$port_hy2"
blue "Tuic-v5端口：$port_tu"
blue "AnyTLS端口：$port_anytls"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "四、自動生成各個協議統一的uuid (密碼)"
uuid=$(/etc/s-box/sing-box generate uuid)
blue "已確認uuid (密碼)：${uuid}"
blue "已確認Vmess的path路徑：${uuid}-vm"
}

inssbjsonser(){
cat > /etc/s-box/sb10.json <<EOF
{
"log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "sniff": true,
      "sniff_override_destination": true,
      "tag": "vless-sb",
      "listen": "::",
      "listen_port": ${port_vl_re},
      "users": [
        {
          "uuid": "${uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${ym_vl_re}",
          "reality": {
          "enabled": true,
          "handshake": {
            "server": "${ym_vl_re}",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    },
{
        "type": "vmess",
        "sniff": true,
        "sniff_override_destination": true,
        "tag": "vmess-sb",
        "listen": "::",
        "listen_port": ${port_vm_ws},
        "users": [
            {
                "uuid": "${uuid}",
                "alterId": 0
            }
        ],
        "transport": {
            "type": "ws",
            "path": "${uuid}-vm",
            "max_early_data":2048,
            "early_data_header_name": "Sec-WebSocket-Protocol"    
        },
        "tls":{
                "enabled": ${tlsyn},
                "server_name": "${ym_vm_ws}",
                "certificate_path": "$certificatec_vmess_ws",
                "key_path": "$certificatep_vmess_ws"
            }
    }, 
    {
        "type": "hysteria2",
        "sniff": true,
        "sniff_override_destination": true,
        "tag": "hy2-sb",
        "listen": "::",
        "listen_port": ${port_hy2},
        "users": [
            {
                "password": "${uuid}"
            }
        ],
        "ignore_client_bandwidth":false,
        "tls": {
            "enabled": true,
            "alpn": [
                "h3"
            ],
            "certificate_path": "$certificatec_hy2",
            "key_path": "$certificatep_hy2"
        }
    },
        {
            "type":"tuic",
            "sniff": true,
            "sniff_override_destination": true,
            "tag": "tuic5-sb",
            "listen": "::",
            "listen_port": ${port_tu},
            "users": [
                {
                    "uuid": "${uuid}",
                    "password": "${uuid}"
                }
            ],
            "congestion_control": "bbr",
            "tls":{
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "certificate_path": "$certificatec_tuic",
                "key_path": "$certificatep_tuic"
            }
        },
        {
            "type": "anytls",
            "tag": "anytls-sb",
            "listen": "::",
            "listen_port": ${port_anytls},
            "users": [
                {
                    "name": "anytls_user",
                    "password": "${uuid}"
                }
            ],
            "padding_scheme": [
                "stop=8",
                "0=30-30",
                "1=100-400",
                "2=400-500,c,500-1000,c,500-1000,c,500-1000,c,500-1000",
                "3=9-9,500-1000",
                "4=500-1000",
                "5=500-1000",
                "6=500-1000",
                "7=500-1000"
            ],
            "tls": {
                "enabled": true,
                "server_name": "${ym_vl_re}",
                "reality": {
                    "enabled": true,
                    "handshake": {
                        "server": "${ym_vl_re}",
                        "server_port": 443
                    },
                    "private_key": "$private_key",
                    "short_id": ["$short_id"]
                }
            }
        }
],
"outbounds": [
{
"type":"direct",
"tag":"direct",
"domain_strategy": "$ipv"
},
{
"type":"direct",
"tag": "vps-outbound-v4", 
"domain_strategy":"prefer_ipv4"
},
{
"type":"direct",
"tag": "vps-outbound-v6",
"domain_strategy":"prefer_ipv6"
},
{
"type": "socks",
"tag": "socks-out",
"server": "127.0.0.1",
"server_port": 40000,
"version": "5"
},
{
"type":"direct",
"tag":"socks-IPv4-out",
"detour":"socks-out",
"domain_strategy":"prefer_ipv4"
},
{
"type":"direct",
"tag":"socks-IPv6-out",
"detour":"socks-out",
"domain_strategy":"prefer_ipv6"
},
{
"type":"direct",
"tag":"warp-IPv4-out",
"detour":"wireguard-out",
"domain_strategy":"prefer_ipv4"
},
{
"type":"direct",
"tag":"warp-IPv6-out",
"detour":"wireguard-out",
"domain_strategy":"prefer_ipv6"
},
{
"type":"wireguard",
"tag":"wireguard-out",
"server":"$endip",
"server_port":2408,
"local_address":[
"172.16.0.2/32",
"${v6}/128"
],
"private_key":"$pvk",
"peer_public_key":"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
"reserved":$res
},
{
"type": "block",
"tag": "block"
}
],
"route":{
"rules":[
{
"protocol": [
"quic",
"stun"
],
"outbound": "block"
},
{
"outbound":"warp-IPv4-out",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"warp-IPv6-out",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"socks-IPv4-out",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"socks-IPv6-out",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"vps-outbound-v4",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"vps-outbound-v6",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound": "direct",
"network": "udp,tcp"
}
]
}
}
EOF

cat > /etc/s-box/sb11.json <<EOF
{
"log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",

      
      "tag": "vless-sb",
      "listen": "::",
      "listen_port": ${port_vl_re},
      "users": [
        {
          "uuid": "${uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${ym_vl_re}",
          "reality": {
          "enabled": true,
          "handshake": {
            "server": "${ym_vl_re}",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    },
{
        "type": "vmess",

 
        "tag": "vmess-sb",
        "listen": "::",
        "listen_port": ${port_vm_ws},
        "users": [
            {
                "uuid": "${uuid}",
                "alterId": 0
            }
        ],
        "transport": {
            "type": "ws",
            "path": "${uuid}-vm",
            "max_early_data":2048,
            "early_data_header_name": "Sec-WebSocket-Protocol"    
        },
        "tls":{
                "enabled": ${tlsyn},
                "server_name": "${ym_vm_ws}",
                "certificate_path": "$certificatec_vmess_ws",
                "key_path": "$certificatep_vmess_ws"
            }
    }, 
    {
        "type": "hysteria2",

 
        "tag": "hy2-sb",
        "listen": "::",
        "listen_port": ${port_hy2},
        "users": [
            {
                "password": "${uuid}"
            }
        ],
        "ignore_client_bandwidth":false,
        "tls": {
            "enabled": true,
            "alpn": [
                "h3"
            ],
            "certificate_path": "$certificatec_hy2",
            "key_path": "$certificatep_hy2"
        }
    },
        {
            "type":"tuic",

     
            "tag": "tuic5-sb",
            "listen": "::",
            "listen_port": ${port_tu},
            "users": [
                {
                    "uuid": "${uuid}",
                    "password": "${uuid}"
                }
            ],
            "congestion_control": "bbr",
            "tls":{
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "certificate_path": "$certificatec_tuic",
                "key_path": "$certificatep_tuic"
            }
        },
        {
            "type": "anytls",
            "tag": "anytls-sb",
            "listen": "::",
            "listen_port": ${port_anytls},
            "users": [
                {
                    "name": "anytls_user",
                    "password": "${uuid}"
                }
            ],
            "padding_scheme": [
                "stop=8",
                "0=30-30",
                "1=100-400",
                "2=400-500,c,500-1000,c,500-1000,c,500-1000,c,500-1000",
                "3=9-9,500-1000",
                "4=500-1000",
                "5=500-1000",
                "6=500-1000",
                "7=500-1000"
            ],
            "tls": {
                "enabled": true,
                "server_name": "${ym_vl_re}",
                "reality": {
                    "enabled": true,
                    "handshake": {
                        "server": "${ym_vl_re}",
                        "server_port": 443
                    },
                    "private_key": "$private_key",
                    "short_id": ["$short_id"]
                }
            }
        }
],
"endpoints":[
{
"type":"wireguard",
"tag":"warp-out",
"address":[
"172.16.0.2/32",
"${v6}/128"
],
"private_key":"$pvk",
"peers": [
{
"address": "$endip",
"port":2408,
"public_key":"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
"allowed_ips": [
"0.0.0.0/0",
"::/0"
],
"reserved":$res
}
]
}
],
"outbounds": [
{
"type":"direct",
"tag":"direct",
"domain_strategy": "$ipv"
},
{
"type":"direct",
"tag":"vps-outbound-v4", 
"domain_strategy":"prefer_ipv4"
},
{
"type":"direct",
"tag":"vps-outbound-v6",
"domain_strategy":"prefer_ipv6"
},
{
"type": "socks",
"tag": "socks-out",
"server": "127.0.0.1",
"server_port": 40000,
"version": "5"
}
],
"route":{
"rules":[
{
 "action": "sniff"
},
{
"action": "resolve",
"domain_suffix":[
"yg_kkk"
],
"strategy": "prefer_ipv4"
},
{
"action": "resolve",
"domain_suffix":[
"yg_kkk"
],
"strategy": "prefer_ipv6"
},
{
"domain_suffix":[
"yg_kkk"
],
"outbound":"socks-out"
},
{
"domain_suffix":[
"yg_kkk"
],
"outbound":"warp-out"
},
{
"outbound":"vps-outbound-v4",
"domain_suffix":[
"yg_kkk"
]
},
{
"outbound":"vps-outbound-v6",
"domain_suffix":[
"yg_kkk"
]
},
{
"outbound": "direct",
"network": "udp,tcp"
}
]
}
}
EOF
sbnh=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}' | cut -d '.' -f 1,2)
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
}

sbservice(){
if [[ x"${release}" == x"alpine" ]]; then
echo '#!/sbin/openrc-run
description="sing-box service"
command="/etc/s-box/sing-box"
command_args="run -c /etc/s-box/sb.json"
command_background=true
pidfile="/var/run/sing-box.pid"' > /etc/init.d/sing-box
chmod +x /etc/init.d/sing-box
rc-update add sing-box default
rc-service sing-box start
else
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
After=network.target nss-lookup.target
[Service]
User=root
WorkingDirectory=/root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/etc/s-box/sing-box run -c /etc/s-box/sb.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable sing-box >/dev/null 2>&1
systemctl start sing-box
systemctl restart sing-box
fi
}

ipuuid(){
if [[ x"${release}" == x"alpine" ]]; then
status_cmd="rc-service sing-box status"
status_pattern="started"
else
status_cmd="systemctl status sing-box"
status_pattern="active"
fi
if [[ -n $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f '/etc/s-box/sb.json' ]]; then
v4v6
if [[ -n $v4 && -n $v6 ]]; then
green "雙棧VPS需要選擇IP配置輸出，一般情況下nat vps建議選擇IPV6"
yellow "1：使用IPV4配置輸出 (回車默認) "
yellow "2：使用IPV6配置輸出"
readp "請選擇【1-2】：" menu
if [ -z "$menu" ] || [ "$menu" = "1" ]; then
sbdnsip='tls://8.8.8.8/dns-query'
echo "$sbdnsip" > /etc/s-box/sbdnsip.log
server_ip="$v4"
echo "$server_ip" > /etc/s-box/server_ip.log
server_ipcl="$v4"
echo "$server_ipcl" > /etc/s-box/server_ipcl.log
else
sbdnsip='tls://[2001:4860:4860::8888]/dns-query'
echo "$sbdnsip" > /etc/s-box/sbdnsip.log
server_ip="[$v6]"
echo "$server_ip" > /etc/s-box/server_ip.log
server_ipcl="$v6"
echo "$server_ipcl" > /etc/s-box/server_ipcl.log
fi
else
yellow "VPS並不是雙棧VPS，不支持IP配置輸出的切換"
serip=$(curl -s4m5 icanhazip.com -k || curl -s6m5 icanhazip.com -k)
if [[ "$serip" =~ : ]]; then
sbdnsip='tls://[2001:4860:4860::8888]/dns-query'
echo "$sbdnsip" > /etc/s-box/sbdnsip.log
server_ip="[$serip]"
echo "$server_ip" > /etc/s-box/server_ip.log
server_ipcl="$serip"
echo "$server_ipcl" > /etc/s-box/server_ipcl.log
else
sbdnsip='tls://8.8.8.8/dns-query'
echo "$sbdnsip" > /etc/s-box/sbdnsip.log
server_ip="$serip"
echo "$server_ip" > /etc/s-box/server_ip.log
server_ipcl="$serip"
echo "$server_ipcl" > /etc/s-box/server_ipcl.log
fi
fi
else
red "Sing-box服務未運行" && exit
fi
}

wgcfgo(){
warpcheck
if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
ipuuid
else
systemctl stop wg-quick@wgcf >/dev/null 2>&1
kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
ipuuid
systemctl start wg-quick@wgcf >/dev/null 2>&1
systemctl restart warp-go >/dev/null 2>&1
systemctl enable warp-go >/dev/null 2>&1
systemctl start warp-go >/dev/null 2>&1
fi
}

result_vl_vm_hy_tu(){
if [[ -f /root/ygkkkca/cert.crt && -f /root/ygkkkca/private.key && -s /root/ygkkkca/cert.crt && -s /root/ygkkkca/private.key ]]; then
ym=`bash ~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}'`
echo $ym > /root/ygkkkca/ca.log
fi
rm -rf /etc/s-box/vm_ws_argo.txt /etc/s-box/vm_ws.txt /etc/s-box/vm_ws_tls.txt
sbdnsip=$(cat /etc/s-box/sbdnsip.log)
server_ip=$(cat /etc/s-box/server_ip.log)
server_ipcl=$(cat /etc/s-box/server_ipcl.log)
uuid=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].users[0].uuid')
vl_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].listen_port')
vl_name=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.server_name')
public_key=$(cat /etc/s-box/public.key)
short_id=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.reality.short_id[0]')
argo=$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
ws_path=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].transport.path')
vm_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port')
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
vm_name=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.server_name')
if [[ "$tls" = "false" ]]; then
if [[ -f /etc/s-box/cfymjx.txt ]]; then
vm_name=$(cat /etc/s-box/cfymjx.txt 2>/dev/null)
else
vm_name=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.server_name')
fi
vmadd_local=$server_ipcl
vmadd_are_local=$server_ip
else
vmadd_local=$vm_name
vmadd_are_local=$vm_name
fi
if [[ -f /etc/s-box/cfvmadd_local.txt ]]; then
vmadd_local=$(cat /etc/s-box/cfvmadd_local.txt 2>/dev/null)
vmadd_are_local=$(cat /etc/s-box/cfvmadd_local.txt 2>/dev/null)
else
if [[ "$tls" = "false" ]]; then
if [[ -f /etc/s-box/cfymjx.txt ]]; then
vm_name=$(cat /etc/s-box/cfymjx.txt 2>/dev/null)
else
vm_name=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.server_name')
fi
vmadd_local=$server_ipcl
vmadd_are_local=$server_ip
else
vmadd_local=$vm_name
vmadd_are_local=$vm_name
fi
fi
if [[ -f /etc/s-box/cfvmadd_argo.txt ]]; then
vmadd_argo=$(cat /etc/s-box/cfvmadd_argo.txt 2>/dev/null)
else
vmadd_argo=www.visa.com.sg
fi
hy2_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].listen_port')
hy2_ports=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$hy2_port" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ',' | sed 's/,$//')
if [[ -n $hy2_ports ]]; then
hy2ports=$(echo $hy2_ports | sed 's/:/-/g')
hyps=$hy2_port,$hy2ports
else
hyps=
fi
ym=$(cat /root/ygkkkca/ca.log 2>/dev/null)
hy2_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].tls.key_path')
if [[ "$hy2_sniname" = '/etc/s-box/private.key' ]]; then
hy2_name=www.bing.com
sb_hy2_ip=$server_ip
cl_hy2_ip=$server_ipcl
ins_hy2=1
hy2_ins=true
else
hy2_name=$ym
sb_hy2_ip=$ym
cl_hy2_ip=$ym
ins_hy2=0
hy2_ins=false
fi
tu5_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].listen_port')
ym=$(cat /root/ygkkkca/ca.log 2>/dev/null)
tu5_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.key_path')
if [[ "$tu5_sniname" = '/etc/s-box/private.key' ]]; then
tu5_name=www.bing.com
sb_tu5_ip=$server_ip
cl_tu5_ip=$server_ipcl
ins=1
tu5_ins=true
else
tu5_name=$ym
sb_tu5_ip=$ym
cl_tu5_ip=$ym
ins=0
tu5_ins=false
fi
anytls_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[4].listen_port')
}

resvless(){
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
vl_link="vless://$uuid@$server_ip:$vl_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$vl_name&fp=firefox&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#vl-reality-$hostname"
echo "$vl_link" > /etc/s-box/vl_reality.txt
red "🚀【 vless-reality-vision 】節點信息如下：" && sleep 2
echo
echo "分享鏈接【v2ran(切換singbox內核)、nekobox、小火箭shadowrocket】"
echo -e "${yellow}$vl_link${plain}"
echo
echo "二維碼【v2ran(切換singbox內核)、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vl_reality.txt)"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

resvmess(){
if [[ "$tls" = "false" ]]; then
argopid
if [[ -n $(ps -e | grep -w $ls 2>/dev/null) ]]; then
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws(tls)+Argo 】臨時節點信息如下(可選擇3-8-3，自定義CDN優選地址)：" && sleep 2
echo
echo "分享鏈接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argo'","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "二維碼【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo 'vmess://'$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argo'","type":"none","v":"2"}' | base64 -w 0) > /etc/s-box/vm_ws_argols.txt
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vm_ws_argols.txt)"
fi
if [[ -n $(ps -e | grep -w $ym 2>/dev/null) ]]; then
argogd=$(cat /etc/s-box/sbargoym.log 2>/dev/null)
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws(tls)+Argo 】固定節點信息如下 (可選擇3-8-3，自定義CDN優選地址)：" && sleep 2
echo
echo "分享鏈接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argogd'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argogd'","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "二維碼【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo 'vmess://'$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argogd'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argogd'","type":"none","v":"2"}' | base64 -w 0) > /etc/s-box/vm_ws_argogd.txt
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vm_ws_argogd.txt)"
fi
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws 】節點信息如下 (建議選擇3-8-1，設置為CDN優選節點)：" && sleep 2
echo
echo "分享鏈接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-$hostname'","tls":"","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "二維碼【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo 'vmess://'$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-$hostname'","tls":"","type":"none","v":"2"}' | base64 -w 0) > /etc/s-box/vm_ws.txt
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vm_ws.txt)"
else
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws-tls 】節點信息如下 (建議選擇3-8-1，設置為CDN優選節點)：" && sleep 2
echo
echo "分享鏈接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-tls-$hostname'","tls":"tls","sni":"'$vm_name'","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "二維碼【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo 'vmess://'$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-tls-$hostname'","tls":"tls","sni":"'$vm_name'","type":"none","v":"2"}' | base64 -w 0) > /etc/s-box/vm_ws_tls.txt
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vm_ws_tls.txt)"
fi
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

reshy2(){
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
#hy2_link="hysteria2://$uuid@$sb_hy2_ip:$hy2_port?security=tls&alpn=h3&insecure=$ins_hy2&mport=$hyps&sni=$hy2_name#hy2-$hostname"
hy2_link="hysteria2://$uuid@$sb_hy2_ip:$hy2_port?security=tls&alpn=h3&insecure=$ins_hy2&sni=$hy2_name#hy2-$hostname"
echo "$hy2_link" > /etc/s-box/hy2.txt
red "🚀【 Hysteria-2 】節點信息如下：" && sleep 2
echo
echo "分享鏈接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}$hy2_link${plain}"
echo
echo "二維碼【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/hy2.txt)"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

restu5(){
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
tuic5_link="tuic://$uuid:$uuid@$sb_tu5_ip:$tu5_port?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=$tu5_name&allow_insecure=$ins&allowInsecure=$ins#tu5-$hostname"
echo "$tuic5_link" > /etc/s-box/tuic5.txt
red "🚀【 Tuic-v5 】節點信息如下：" && sleep 2
echo
echo "分享鏈接【v2rayn、nekobox、小火箭shadowrocket】"
echo -e "${yellow}$tuic5_link${plain}"
echo
echo "二維碼【v2rayn、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/tuic5.txt)"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

resanytls(){
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
# AnyTLS-Reality 格式: anytls://password@server:port?sni=sni&pbk=public_key&sid=short_id&utls=firefox#name
anytls_link="anytls://$uuid@$server_ip:$anytls_port?sni=$vl_name&pbk=$public_key&sid=$short_id&utls=firefox&fp=firefox#anytls-$hostname"
echo "$anytls_link" > /etc/s-box/anytls.txt
red "🚀【 AnyTLS-Reality 】節點信息如下：" && sleep 2
echo
echo "分享鏈接【nekobox、SFA、SFI】"
echo -e "${yellow}$anytls_link${plain}"
echo
echo "二維碼【nekobox、SFA、SFI】"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/anytls.txt)"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

sb_client(){
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
argopid
if [[ -n $(ps -e | grep -w $ym 2>/dev/null) && -n $(ps -e | grep -w $ls 2>/dev/null) && "$tls" = "false" ]]; then
cat > /etc/s-box/sing_box_client.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "experimental": {
    "clash_api": {
      "external_controller": "127.0.0.1:9090",
      "external_ui": "ui",
      "external_ui_download_url": "",
      "external_ui_download_detour": "",
      "secret": "",
      "default_mode": "Rule"
       },
      "cache_file": {
            "enabled": true,
            "path": "cache.db",
            "store_fakeip": true
        }
    },
    "dns": {
        "servers": [
            {
                "tag": "proxydns",
                "address": "$sbdnsip",
                "detour": "select"
            },
            {
                "tag": "localdns",
                "address": "h3://223.5.5.5/dns-query",
                "detour": "direct"
            },
            {
                "tag": "dns_fakeip",
                "address": "fakeip"
            }
        ],
        "rules": [
            {
                "outbound": "any",
                "server": "localdns",
                "disable_cache": true
            },
            {
                "clash_mode": "Global",
                "server": "proxydns"
            },
            {
                "clash_mode": "Direct",
                "server": "localdns"
            },
            {
                "rule_set": "geosite-cn",
                "server": "localdns"
            },
            {
                 "rule_set": "geosite-geolocation-!cn",
                 "server": "proxydns"
            },
             {
                "rule_set": "geosite-geolocation-!cn",         
                "query_type": [
                    "A",
                    "AAAA"
                ],
                "server": "dns_fakeip"
            }
          ],
           "fakeip": {
           "enabled": true,
           "inet4_range": "198.18.0.0/15",
           "inet6_range": "fc00::/18"
         },
          "independent_cache": true,
          "final": "proxydns"
        },
      "inbounds": [
    {
      "type": "tun",
           "tag": "tun-in",
	  "address": [
      "172.19.0.1/30",
	  "fd00::1/126"
      ],
      "auto_route": true,
      "strict_route": true,
      "sniff": true,
      "sniff_override_destination": true,
      "domain_strategy": "prefer_ipv4"
    }
  ],
  "outbounds": [
    {
      "tag": "select",
      "type": "selector",
      "default": "auto",
      "outbounds": [
        "auto",
        "vless-$hostname",
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname",
        "anytls-$hostname",
"vmess-tls-argo固定-$hostname",
"vmess-argo固定-$hostname",
"vmess-tls-argo臨時-$hostname",
"vmess-argo臨時-$hostname"
      ]
    },
    {
      "type": "vless",
      "tag": "vless-$hostname",
      "server": "$server_ipcl",
      "server_port": $vl_port,
      "uuid": "$uuid",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "$vl_name",
        "utls": {
          "enabled": true,
          "fingerprint": "firefox"
        },
      "reality": {
          "enabled": true,
          "public_key": "$public_key",
          "short_id": "$short_id"
        }
      }
    },
{
            "server": "$vmadd_local",
            "server_port": $vm_port,
            "tag": "vmess-$hostname",
            "tls": {
                "enabled": $tls,
                "server_name": "$vm_name",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "firefox"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$vm_name"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },

    {
        "type": "hysteria2",
        "tag": "hy2-$hostname",
        "server": "$cl_hy2_ip",
        "server_port": $hy2_port,
        "password": "$uuid",
        "tls": {
            "enabled": true,
            "server_name": "$hy2_name",
            "insecure": $hy2_ins,
            "alpn": [
                "h3"
            ]
        }
    },
        {
            "type":"tuic",
            "tag": "tuic5-$hostname",
            "server": "$cl_tu5_ip",
            "server_port": $tu5_port,
            "uuid": "$uuid",
            "password": "$uuid",
            "congestion_control": "bbr",
            "udp_relay_mode": "native",
            "udp_over_stream": false,
            "zero_rtt_handshake": false,
            "heartbeat": "10s",
            "tls":{
                "enabled": true,
                "server_name": "$tu5_name",
                "insecure": $tu5_ins,
                "alpn": [
                    "h3"
                ]
            }
        },
        {
            "type": "anytls",
            "tag": "anytls-$hostname",
            "server": "$server_ipcl",
            "server_port": $anytls_port,
            "password": "$uuid",
            "idle_session_check_interval": "30s",
            "idle_session_timeout": "30s",
            "min_idle_session": 5,
            "tls": {
                "enabled": true,
                "disable_sni": false,
                "server_name": "$vl_name",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "firefox"
                },
                "reality": {
                    "enabled": true,
                    "public_key": "$public_key",
                    "short_id": "$short_id"
                }
            }
        },
{
            "server": "$vmadd_argo",
            "server_port": 8443,
            "tag": "vmess-tls-argo固定-$hostname",
            "tls": {
                "enabled": true,
                "server_name": "$argogd",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "firefox"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argogd"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
{
            "server": "$vmadd_argo",
            "server_port": 8880,
            "tag": "vmess-argo固定-$hostname",
            "tls": {
                "enabled": false,
                "server_name": "$argogd",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "firefox"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argogd"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
{
            "server": "$vmadd_argo",
            "server_port": 8443,
            "tag": "vmess-tls-argo臨時-$hostname",
            "tls": {
                "enabled": true,
                "server_name": "$argo",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "firefox"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argo"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
{
            "server": "$vmadd_argo",
            "server_port": 8880,
            "tag": "vmess-argo臨時-$hostname",
            "tls": {
                "enabled": false,
                "server_name": "$argo",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "firefox"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argo"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
    {
      "tag": "direct",
      "type": "direct"
    },
    {
      "tag": "auto",
      "type": "urltest",
      "outbounds": [
        "vless-$hostname",
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname",
        "anytls-$hostname",
"vmess-tls-argo固定-$hostname",
"vmess-argo固定-$hostname",
"vmess-tls-argo臨時-$hostname",
"vmess-argo臨時-$hostname"
      ],
      "url": "https://www.gstatic.com/generate_204",
      "interval": "1m",
      "tolerance": 50,
      "interrupt_exist_connections": false
    }
  ],
  "route": {
      "rule_set": [
            {
                "tag": "geosite-geolocation-!cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-!cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            },
            {
                "tag": "geosite-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            },
            {
                "tag": "geoip-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            }
        ],
    "auto_detect_interface": true,
    "final": "select",
    "rules": [
      {
      "inbound": "tun-in",
      "action": "sniff"
      },
      {
      "protocol": "dns",
      "action": "hijack-dns"
      },
      {
      "port": 443,
      "network": "udp",
      "action": "reject"
      },
      {
        "clash_mode": "Direct",
        "outbound": "direct"
      },
      {
        "clash_mode": "Global",
        "outbound": "select"
      },
      {
        "rule_set": "geoip-cn",
        "outbound": "direct"
      },
      {
        "rule_set": "geosite-cn",
        "outbound": "direct"
      },
      {
      "ip_is_private": true,
      "outbound": "direct"
      },
      {
        "rule_set": "geosite-geolocation-!cn",
        "outbound": "select"
      }
    ]
  },
    "ntp": {
    "enabled": true,
    "server": "time.apple.com",
    "server_port": 123,
    "interval": "30m",
    "detour": "direct"
  }
}
EOF

cat > /etc/s-box/clash_meta_client.yaml <<EOF
port: 7890
allow-lan: true
mode: rule
log-level: info
unified-delay: true
global-client-fingerprint: firefox
dns:
  enable: false
  listen: :53
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver: 
    - 223.5.5.5
    - 8.8.8.8
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - tls://dns.google
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4

proxies:
- name: vless-reality-vision-$hostname               
  type: vless
  server: $server_ipcl                           
  port: $vl_port                                
  uuid: $uuid   
  network: tcp
  udp: true
  tls: true
  flow: xtls-rprx-vision
  servername: $vl_name                 
  reality-opts: 
    public-key: $public_key    
    short-id: $short_id                      
  client-fingerprint: firefox                  

- name: vmess-ws-$hostname                         
  type: vmess
  server: $vmadd_local                        
  port: $vm_port                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: $tls
  network: ws
  servername: $vm_name                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $vm_name                     

- name: hysteria2-$hostname                            
  type: hysteria2                                      
  server: $cl_hy2_ip                               
  port: $hy2_port                                
  password: $uuid                          
  alpn:
    - h3
  sni: $hy2_name                               
  skip-cert-verify: $hy2_ins
  fast-open: true

- name: tuic5-$hostname                            
  server: $cl_tu5_ip                      
  port: $tu5_port                                    
  type: tuic
  uuid: $uuid       
  password: $uuid   
  alpn: [h3]
  disable-sni: true
  reduce-rtt: true
  udp-relay-mode: native
  congestion-controller: bbr
  sni: $tu5_name                                
  skip-cert-verify: $tu5_ins

- name: anytls-$hostname
  type: anytls
  server: $server_ipcl
  port: $anytls_port
  password: $uuid
  sni: $vl_name
  client-fingerprint: firefox
  reality-opts:
    public-key: $public_key
    short-id: $short_id

- name: vmess-tls-argo固定-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8443                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: true
  network: ws
  servername: $argogd                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $argogd


- name: vmess-argo固定-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8880                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: false
  network: ws
  servername: $argogd                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $argogd

- name: vmess-tls-argo臨時-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8443                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: true
  network: ws
  servername: $argo                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $argo

- name: vmess-argo臨時-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8880                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: false
  network: ws
  servername: $argo                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $argo 

proxy-groups:
- name: 負載均衡
  type: load-balance
  url: https://www.gstatic.com/generate_204
  interval: 300
  strategy: round-robin
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    - anytls-$hostname
    - vmess-tls-argo固定-$hostname
    - vmess-argo固定-$hostname
    - vmess-tls-argo臨時-$hostname
    - vmess-argo臨時-$hostname

- name: 自動選擇
  type: url-test
  url: https://www.gstatic.com/generate_204
  interval: 300
  tolerance: 50
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    - vmess-tls-argo固定-$hostname
    - anytls-$hostname
    - vmess-argo固定-$hostname
    - vmess-tls-argo臨時-$hostname
    - vmess-argo臨時-$hostname
    
- name: 🌍選擇代理節點
  type: select
  proxies:
    - 負載均衡                                         
    - 自動選擇
    - DIRECT
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    - anytls-$hostname
    - vmess-tls-argo固定-$hostname
    - vmess-argo固定-$hostname
    - vmess-tls-argo臨時-$hostname
    - vmess-argo臨時-$hostname
rules:
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,🌍選擇代理節點
EOF


elif [[ ! -n $(ps -e | grep -w $ym 2>/dev/null) && -n $(ps -e | grep -w $ls 2>/dev/null) && "$tls" = "false" ]]; then
cat > /etc/s-box/sing_box_client.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "experimental": {
    "clash_api": {
      "external_controller": "127.0.0.1:9090",
      "external_ui": "ui",
      "external_ui_download_url": "",
      "external_ui_download_detour": "",
      "secret": "",
      "default_mode": "Rule"
       },
      "cache_file": {
            "enabled": true,
            "path": "cache.db",
            "store_fakeip": true
        }
    },
    "dns": {
        "servers": [
            {
                "tag": "proxydns",
                "address": "$sbdnsip",
                "detour": "select"
            },
            {
                "tag": "localdns",
                "address": "h3://223.5.5.5/dns-query",
                "detour": "direct"
            },
            {
                "tag": "dns_fakeip",
                "address": "fakeip"
            }
        ],
        "rules": [
            {
                "outbound": "any",
                "server": "localdns",
                "disable_cache": true
            },
            {
                "clash_mode": "Global",
                "server": "proxydns"
            },
            {
                "clash_mode": "Direct",
                "server": "localdns"
            },
            {
                "rule_set": "geosite-cn",
                "server": "localdns"
            },
            {
                 "rule_set": "geosite-geolocation-!cn",
                 "server": "proxydns"
            },
             {
                "rule_set": "geosite-geolocation-!cn",         
                "query_type": [
                    "A",
                    "AAAA"
                ],
                "server": "dns_fakeip"
            }
          ],
           "fakeip": {
           "enabled": true,
           "inet4_range": "198.18.0.0/15",
           "inet6_range": "fc00::/18"
         },
          "independent_cache": true,
          "final": "proxydns"
        },
      "inbounds": [
    {
      "type": "tun",
           "tag": "tun-in",
	  "address": [
      "172.19.0.1/30",
	  "fd00::1/126"
      ],
      "auto_route": true,
      "strict_route": true,
      "sniff": true,
      "sniff_override_destination": true,
      "domain_strategy": "prefer_ipv4"
    }
  ],
  "outbounds": [
    {
      "tag": "select",
      "type": "selector",
      "default": "auto",
      "outbounds": [
        "auto",
        "vless-$hostname",
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname",
        "anytls-$hostname",
"vmess-tls-argo臨時-$hostname",
"vmess-argo臨時-$hostname"
      ]
    },
    {
      "type": "vless",
      "tag": "vless-$hostname",
      "server": "$server_ipcl",
      "server_port": $vl_port,
      "uuid": "$uuid",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "$vl_name",
        "utls": {
          "enabled": true,
          "fingerprint": "firefox"
        },
      "reality": {
          "enabled": true,
          "public_key": "$public_key",
          "short_id": "$short_id"
        }
      }
    },
{
            "server": "$vmadd_local",
            "server_port": $vm_port,
            "tag": "vmess-$hostname",
            "tls": {
                "enabled": $tls,
                "server_name": "$vm_name",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "firefox"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$vm_name"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },

    {
        "type": "hysteria2",
        "tag": "hy2-$hostname",
        "server": "$cl_hy2_ip",
        "server_port": $hy2_port,
        "password": "$uuid",
        "tls": {
            "enabled": true,
            "server_name": "$hy2_name",
            "insecure": $hy2_ins,
            "alpn": [
                "h3"
            ]
        }
    },
        {
            "type":"tuic",
            "tag": "tuic5-$hostname",
            "server": "$cl_tu5_ip",
            "server_port": $tu5_port,
            "uuid": "$uuid",
            "password": "$uuid",
            "congestion_control": "bbr",
            "udp_relay_mode": "native",
            "udp_over_stream": false,
            "zero_rtt_handshake": false,
            "heartbeat": "10s",
            "tls":{
                "enabled": true,
                "server_name": "$tu5_name",
                "insecure": $tu5_ins,
                "alpn": [
                    "h3"
                ]
            }
        },
        {
            "type": "anytls",
            "tag": "anytls-$hostname",
            "server": "$server_ipcl",
            "server_port": $anytls_port,
            "password": "$uuid",
            "idle_session_check_interval": "30s",
            "idle_session_timeout": "30s",
            "min_idle_session": 5,
            "tls": {
                "enabled": true,
                "disable_sni": false,
                "server_name": "$vl_name",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "firefox"
                },
                "reality": {
                    "enabled": true,
                    "public_key": "$public_key",
                    "short_id": "$short_id"
                }
            }
        },
{
            "server": "$vmadd_argo",
            "server_port": 8443,
            "tag": "vmess-tls-argo臨時-$hostname",
            "tls": {
                "enabled": true,
                "server_name": "$argo",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "firefox"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argo"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
{
            "server": "$vmadd_argo",
            "server_port": 8880,
            "tag": "vmess-argo臨時-$hostname",
            "tls": {
                "enabled": false,
                "server_name": "$argo",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "firefox"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argo"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
    {
      "tag": "direct",
      "type": "direct"
    },
    {
      "tag": "auto",
      "type": "urltest",
      "outbounds": [
        "vless-$hostname",
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname",
        "anytls-$hostname",
"vmess-tls-argo臨時-$hostname",
"vmess-argo臨時-$hostname"
      ],
      "url": "https://www.gstatic.com/generate_204",
      "interval": "1m",
      "tolerance": 50,
      "interrupt_exist_connections": false
    }
  ],
  "route": {
      "rule_set": [
            {
                "tag": "geosite-geolocation-!cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-!cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            },
            {
                "tag": "geosite-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            },
            {
                "tag": "geoip-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            }
        ],
    "auto_detect_interface": true,
    "final": "select",
    "rules": [
      {
      "inbound": "tun-in",
      "action": "sniff"
      },
      {
      "protocol": "dns",
      "action": "hijack-dns"
      },
      {
      "port": 443,
      "network": "udp",
      "action": "reject"
      },
      {
        "clash_mode": "Direct",
        "outbound": "direct"
      },
      {
        "clash_mode": "Global",
        "outbound": "select"
      },
      {
        "rule_set": "geoip-cn",
        "outbound": "direct"
      },
      {
        "rule_set": "geosite-cn",
        "outbound": "direct"
      },
      {
      "ip_is_private": true,
      "outbound": "direct"
      },
      {
        "rule_set": "geosite-geolocation-!cn",
        "outbound": "select"
      }
    ]
  },
    "ntp": {
    "enabled": true,
    "server": "time.apple.com",
    "server_port": 123,
    "interval": "30m",
    "detour": "direct"
  }
}
EOF

cat > /etc/s-box/clash_meta_client.yaml <<EOF
port: 7890
allow-lan: true
mode: rule
log-level: info
unified-delay: true
global-client-fingerprint: firefox
dns:
  enable: false
  listen: :53
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver: 
    - 223.5.5.5
    - 8.8.8.8
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - tls://dns.google
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4

proxies:
- name: vless-reality-vision-$hostname               
  type: vless
  server: $server_ipcl                           
  port: $vl_port                                
  uuid: $uuid   
  network: tcp
  udp: true
  tls: true
  flow: xtls-rprx-vision
  servername: $vl_name                 
  reality-opts: 
    public-key: $public_key    
    short-id: $short_id                      
  client-fingerprint: firefox                  

- name: vmess-ws-$hostname                         
  type: vmess
  server: $vmadd_local                        
  port: $vm_port                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: $tls
  network: ws
  servername: $vm_name                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $vm_name                     

- name: hysteria2-$hostname                            
  type: hysteria2                                      
  server: $cl_hy2_ip                               
  port: $hy2_port                                
  password: $uuid                          
  alpn:
    - h3
  sni: $hy2_name                               
  skip-cert-verify: $hy2_ins
  fast-open: true

- name: tuic5-$hostname                            
  server: $cl_tu5_ip                      
  port: $tu5_port                                    
  type: tuic
  uuid: $uuid       
  password: $uuid   
  alpn: [h3]
  disable-sni: true
  reduce-rtt: true
  udp-relay-mode: native
  congestion-controller: bbr
  sni: $tu5_name                                
  skip-cert-verify: $tu5_ins

- name: anytls-$hostname
  type: anytls
  server: $server_ipcl
  port: $anytls_port
  password: $uuid
  sni: $vl_name
  client-fingerprint: firefox
  reality-opts:
    public-key: $public_key
    short-id: $short_id

- name: vmess-tls-argo臨時-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8443                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: true
  network: ws
  servername: $argo                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $argo

- name: vmess-argo臨時-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8880                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: false
  network: ws
  servername: $argo                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $argo 

proxy-groups:
- name: 負載均衡
  type: load-balance
  url: https://www.gstatic.com/generate_204
  interval: 300
  strategy: round-robin
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    - anytls-$hostname
    - vmess-tls-argo臨時-$hostname
    - vmess-argo臨時-$hostname

- name: 自動選擇
  type: url-test
  url: https://www.gstatic.com/generate_204
  interval: 300
  tolerance: 50
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    - anytls-$hostname
    - vmess-tls-argo臨時-$hostname
    - vmess-argo臨時-$hostname
    
- name: 🌍選擇代理節點
  type: select
  proxies:
    - 負載均衡                                         
    - 自動選擇
    - DIRECT
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    - anytls-$hostname
    - vmess-tls-argo臨時-$hostname
    - vmess-argo臨時-$hostname
rules:
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,🌍選擇代理節點
EOF

elif [[ -n $(ps -e | grep -w $ym 2>/dev/null) && ! -n $(ps -e | grep -w $ls 2>/dev/null) && "$tls" = "false" ]]; then
cat > /etc/s-box/sing_box_client.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "experimental": {
    "clash_api": {
      "external_controller": "127.0.0.1:9090",
      "external_ui": "ui",
      "external_ui_download_url": "",
      "external_ui_download_detour": "",
      "secret": "",
      "default_mode": "Rule"
       },
      "cache_file": {
            "enabled": true,
            "path": "cache.db",
            "store_fakeip": true
        }
    },
    "dns": {
        "servers": [
            {
                "tag": "proxydns",
                "address": "$sbdnsip",
                "detour": "select"
            },
            {
                "tag": "localdns",
                "address": "h3://223.5.5.5/dns-query",
                "detour": "direct"
            },
            {
                "tag": "dns_fakeip",
                "address": "fakeip"
            }
        ],
        "rules": [
            {
                "outbound": "any",
                "server": "localdns",
                "disable_cache": true
            },
            {
                "clash_mode": "Global",
                "server": "proxydns"
            },
            {
                "clash_mode": "Direct",
                "server": "localdns"
            },
            {
                "rule_set": "geosite-cn",
                "server": "localdns"
            },
            {
                 "rule_set": "geosite-geolocation-!cn",
                 "server": "proxydns"
            },
             {
                "rule_set": "geosite-geolocation-!cn",         
                "query_type": [
                    "A",
                    "AAAA"
                ],
                "server": "dns_fakeip"
            }
          ],
           "fakeip": {
           "enabled": true,
           "inet4_range": "198.18.0.0/15",
           "inet6_range": "fc00::/18"
         },
          "independent_cache": true,
          "final": "proxydns"
        },
      "inbounds": [
    {
      "type": "tun",
     "tag": "tun-in",
	  "address": [
      "172.19.0.1/30",
	  "fd00::1/126"
      ],
      "auto_route": true,
      "strict_route": true,
      "sniff": true,
      "sniff_override_destination": true,
      "domain_strategy": "prefer_ipv4"
    }
  ],
  "outbounds": [
    {
      "tag": "select",
      "type": "selector",
      "default": "auto",
      "outbounds": [
        "auto",
        "vless-$hostname",
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname",
        "anytls-$hostname",
"vmess-tls-argo固定-$hostname",
"vmess-argo固定-$hostname"
      ]
    },
    {
      "type": "vless",
      "tag": "vless-$hostname",
      "server": "$server_ipcl",
      "server_port": $vl_port,
      "uuid": "$uuid",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "$vl_name",
        "utls": {
          "enabled": true,
          "fingerprint": "firefox"
        },
      "reality": {
          "enabled": true,
          "public_key": "$public_key",
          "short_id": "$short_id"
        }
      }
    },
{
            "server": "$vmadd_local",
            "server_port": $vm_port,
            "tag": "vmess-$hostname",
            "tls": {
                "enabled": $tls,
                "server_name": "$vm_name",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "firefox"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$vm_name"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },

    {
        "type": "hysteria2",
        "tag": "hy2-$hostname",
        "server": "$cl_hy2_ip",
        "server_port": $hy2_port,
        "password": "$uuid",
        "tls": {
            "enabled": true,
            "server_name": "$hy2_name",
            "insecure": $hy2_ins,
            "alpn": [
                "h3"
            ]
        }
    },
        {
            "type":"tuic",
            "tag": "tuic5-$hostname",
            "server": "$cl_tu5_ip",
            "server_port": $tu5_port,
            "uuid": "$uuid",
            "password": "$uuid",
            "congestion_control": "bbr",
            "udp_relay_mode": "native",
            "udp_over_stream": false,
            "zero_rtt_handshake": false,
            "heartbeat": "10s",
            "tls":{
                "enabled": true,
                "server_name": "$tu5_name",
                "insecure": $tu5_ins,
                "alpn": [
                    "h3"
                ]
            }
        },
        {
            "type": "anytls",
            "tag": "anytls-$hostname",
            "server": "$server_ipcl",
            "server_port": $anytls_port,
            "password": "$uuid",
            "idle_session_check_interval": "30s",
            "idle_session_timeout": "30s",
            "min_idle_session": 5,
            "tls": {
                "enabled": true,
                "disable_sni": false,
                "server_name": "$vl_name",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "firefox"
                },
                "reality": {
                    "enabled": true,
                    "public_key": "$public_key",
                    "short_id": "$short_id"
                }
            }
        },
{
            "server": "$vmadd_argo",
            "server_port": 8443,
            "tag": "vmess-tls-argo固定-$hostname",
            "tls": {
                "enabled": true,
                "server_name": "$argogd",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "firefox"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argogd"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
{
            "server": "$vmadd_argo",
            "server_port": 8880,
            "tag": "vmess-argo固定-$hostname",
            "tls": {
                "enabled": false,
                "server_name": "$argogd",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "firefox"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$argogd"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
    {
      "tag": "direct",
      "type": "direct"
    },
    {
      "tag": "auto",
      "type": "urltest",
      "outbounds": [
        "vless-$hostname",
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname",
        "anytls-$hostname",
"vmess-tls-argo固定-$hostname",
"vmess-argo固定-$hostname"
      ],
      "url": "https://www.gstatic.com/generate_204",
      "interval": "1m",
      "tolerance": 50,
      "interrupt_exist_connections": false
    }
  ],
  "route": {
      "rule_set": [
            {
                "tag": "geosite-geolocation-!cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-!cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            },
            {
                "tag": "geosite-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            },
            {
                "tag": "geoip-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            }
        ],
    "auto_detect_interface": true,
    "final": "select",
    "rules": [
      {
      "inbound": "tun-in",
      "action": "sniff"
      },
      {
      "protocol": "dns",
      "action": "hijack-dns"
      },
      {
      "port": 443,
      "network": "udp",
      "action": "reject"
      },
      {
        "clash_mode": "Direct",
        "outbound": "direct"
      },
      {
        "clash_mode": "Global",
        "outbound": "select"
      },
      {
        "rule_set": "geoip-cn",
        "outbound": "direct"
      },
      {
        "rule_set": "geosite-cn",
        "outbound": "direct"
      },
      {
      "ip_is_private": true,
      "outbound": "direct"
      },
      {
        "rule_set": "geosite-geolocation-!cn",
        "outbound": "select"
      }
    ]
  },
    "ntp": {
    "enabled": true,
    "server": "time.apple.com",
    "server_port": 123,
    "interval": "30m",
    "detour": "direct"
  }
}
EOF

cat > /etc/s-box/clash_meta_client.yaml <<EOF
port: 7890
allow-lan: true
mode: rule
log-level: info
unified-delay: true
global-client-fingerprint: firefox
dns:
  enable: false
  listen: :53
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver: 
    - 223.5.5.5
    - 8.8.8.8
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - tls://dns.google
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4

proxies:
- name: vless-reality-vision-$hostname               
  type: vless
  server: $server_ipcl                           
  port: $vl_port                                
  uuid: $uuid   
  network: tcp
  udp: true
  tls: true
  flow: xtls-rprx-vision
  servername: $vl_name                 
  reality-opts: 
    public-key: $public_key    
    short-id: $short_id                      
  client-fingerprint: firefox                  

- name: vmess-ws-$hostname                         
  type: vmess
  server: $vmadd_local                        
  port: $vm_port                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: $tls
  network: ws
  servername: $vm_name                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $vm_name                     

- name: hysteria2-$hostname                            
  type: hysteria2                                      
  server: $cl_hy2_ip                               
  port: $hy2_port                                
  password: $uuid                          
  alpn:
    - h3
  sni: $hy2_name                               
  skip-cert-verify: $hy2_ins
  fast-open: true

- name: tuic5-$hostname                            
  server: $cl_tu5_ip                      
  port: $tu5_port                                    
  type: tuic
  uuid: $uuid       
  password: $uuid   
  alpn: [h3]
  disable-sni: true
  reduce-rtt: true
  udp-relay-mode: native
  congestion-controller: bbr
  sni: $tu5_name                                
  skip-cert-verify: $tu5_ins

- name: anytls-$hostname
  type: anytls
  server: $server_ipcl
  port: $anytls_port
  password: $uuid
  sni: $vl_name
  client-fingerprint: firefox
  reality-opts:
    public-key: $public_key
    short-id: $short_id

- name: vmess-tls-argo固定-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8443                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: true
  network: ws
  servername: $argogd                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $argogd

- name: vmess-argo固定-$hostname                         
  type: vmess
  server: $vmadd_argo                        
  port: 8880                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: false
  network: ws
  servername: $argogd                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $argogd

proxy-groups:
- name: 負載均衡
  type: load-balance
  url: https://www.gstatic.com/generate_204
  interval: 300
  strategy: round-robin
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    - anytls-$hostname
    - vmess-tls-argo固定-$hostname
    - vmess-argo固定-$hostname

- name: 自動選擇
  type: url-test
  url: https://www.gstatic.com/generate_204
  interval: 300
  tolerance: 50
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    - anytls-$hostname
    - vmess-tls-argo固定-$hostname
    - vmess-argo固定-$hostname
    
- name: 🌍選擇代理節點
  type: select
  proxies:
    - 負載均衡                                         
    - 自動選擇
    - DIRECT
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    - anytls-$hostname
    - vmess-tls-argo固定-$hostname
    - vmess-argo固定-$hostname
rules:
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,🌍選擇代理節點
EOF

else
cat > /etc/s-box/sing_box_client.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "experimental": {
    "clash_api": {
      "external_controller": "127.0.0.1:9090",
      "external_ui": "ui",
      "external_ui_download_url": "",
      "external_ui_download_detour": "",
      "secret": "",
      "default_mode": "Rule"
       },
      "cache_file": {
            "enabled": true,
            "path": "cache.db",
            "store_fakeip": true
        }
    },
    "dns": {
        "servers": [
            {
                "tag": "proxydns",
                "address": "$sbdnsip",
                "detour": "select"
            },
            {
                "tag": "localdns",
                "address": "h3://223.5.5.5/dns-query",
                "detour": "direct"
            },
            {
                "tag": "dns_fakeip",
                "address": "fakeip"
            }
        ],
        "rules": [
            {
                "outbound": "any",
                "server": "localdns",
                "disable_cache": true
            },
            {
                "clash_mode": "Global",
                "server": "proxydns"
            },
            {
                "clash_mode": "Direct",
                "server": "localdns"
            },
            {
                "rule_set": "geosite-cn",
                "server": "localdns"
            },
            {
                 "rule_set": "geosite-geolocation-!cn",
                 "server": "proxydns"
            },
             {
                "rule_set": "geosite-geolocation-!cn",         
                "query_type": [
                    "A",
                    "AAAA"
                ],
                "server": "dns_fakeip"
            }
          ],
           "fakeip": {
           "enabled": true,
           "inet4_range": "198.18.0.0/15",
           "inet6_range": "fc00::/18"
         },
          "independent_cache": true,
          "final": "proxydns"
        },
      "inbounds": [
    {
      "type": "tun",
     "tag": "tun-in",
	  "address": [
      "172.19.0.1/30",
	  "fd00::1/126"
      ],
      "auto_route": true,
      "strict_route": true,
      "sniff": true,
      "sniff_override_destination": true,
      "domain_strategy": "prefer_ipv4"
    }
  ],
  "outbounds": [
    {
      "tag": "select",
      "type": "selector",
      "default": "auto",
      "outbounds": [
        "auto",
        "vless-$hostname",
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname"
        "anytls-$hostname",
      ]
    },
    {
      "type": "vless",
      "tag": "vless-$hostname",
      "server": "$server_ipcl",
      "server_port": $vl_port,
      "uuid": "$uuid",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "$vl_name",
        "utls": {
          "enabled": true,
          "fingerprint": "firefox"
        },
      "reality": {
          "enabled": true,
          "public_key": "$public_key",
          "short_id": "$short_id"
        }
      }
    },
{
            "server": "$vmadd_local",
            "server_port": $vm_port,
            "tag": "vmess-$hostname",
            "tls": {
                "enabled": $tls,
                "server_name": "$vm_name",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "firefox"
                }
            },
            "packet_encoding": "packetaddr",
            "transport": {
                "headers": {
                    "Host": [
                        "$vm_name"
                    ]
                },
                "path": "$ws_path",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },

    {
        "type": "hysteria2",
        "tag": "hy2-$hostname",
        "server": "$cl_hy2_ip",
        "server_port": $hy2_port,
        "password": "$uuid",
        "tls": {
            "enabled": true,
            "server_name": "$hy2_name",
            "insecure": $hy2_ins,
            "alpn": [
                "h3"
            ]
        }
    },
        {
            "type":"tuic",
            "tag": "tuic5-$hostname",
            "server": "$cl_tu5_ip",
            "server_port": $tu5_port,
            "uuid": "$uuid",
            "password": "$uuid",
            "congestion_control": "bbr",
            "udp_relay_mode": "native",
            "udp_over_stream": false,
            "zero_rtt_handshake": false,
            "heartbeat": "10s",
            "tls":{
                "enabled": true,
                "server_name": "$tu5_name",
                "insecure": $tu5_ins,
                "alpn": [
                    "h3"
                ]
            }
        },
        {
            "type": "anytls",
            "tag": "anytls-$hostname",
            "server": "$server_ipcl",
            "server_port": $anytls_port,
            "password": "$uuid",
            "idle_session_check_interval": "30s",
            "idle_session_timeout": "30s",
            "min_idle_session": 5,
            "tls": {
                "enabled": true,
                "disable_sni": false,
                "server_name": "$vl_name",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "firefox"
                },
                "reality": {
                    "enabled": true,
                    "public_key": "$public_key",
                    "short_id": "$short_id"
                }
            }
        },
    {
      "tag": "direct",
      "type": "direct"
    },
    {
      "tag": "auto",
      "type": "urltest",
      "outbounds": [
        "vless-$hostname",
        "vmess-$hostname",
        "hy2-$hostname",
        "tuic5-$hostname"
        "anytls-$hostname",
      ],
      "url": "https://www.gstatic.com/generate_204",
      "interval": "1m",
      "tolerance": 50,
      "interrupt_exist_connections": false
    }
  ],
  "route": {
      "rule_set": [
            {
                "tag": "geosite-geolocation-!cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-!cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            },
            {
                "tag": "geosite-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            },
            {
                "tag": "geoip-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            }
        ],
    "auto_detect_interface": true,
    "final": "select",
    "rules": [
      {
      "inbound": "tun-in",
      "action": "sniff"
      },
      {
      "protocol": "dns",
      "action": "hijack-dns"
      },
      {
      "port": 443,
      "network": "udp",
      "action": "reject"
      },
      {
        "clash_mode": "Direct",
        "outbound": "direct"
      },
      {
        "clash_mode": "Global",
        "outbound": "select"
      },
      {
        "rule_set": "geoip-cn",
        "outbound": "direct"
      },
      {
        "rule_set": "geosite-cn",
        "outbound": "direct"
      },
      {
      "ip_is_private": true,
      "outbound": "direct"
      },
      {
        "rule_set": "geosite-geolocation-!cn",
        "outbound": "select"
      }
    ]
  },
    "ntp": {
    "enabled": true,
    "server": "time.apple.com",
    "server_port": 123,
    "interval": "30m",
    "detour": "direct"
  }
}
EOF

cat > /etc/s-box/clash_meta_client.yaml <<EOF
port: 7890
allow-lan: true
mode: rule
log-level: info
unified-delay: true
global-client-fingerprint: firefox
dns:
  enable: false
  listen: :53
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver: 
    - 223.5.5.5
    - 8.8.8.8
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - tls://dns.google
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4

proxies:
- name: vless-reality-vision-$hostname               
  type: vless
  server: $server_ipcl                           
  port: $vl_port                                
  uuid: $uuid   
  network: tcp
  udp: true
  tls: true
  flow: xtls-rprx-vision
  servername: $vl_name                 
  reality-opts: 
    public-key: $public_key    
    short-id: $short_id                    
  client-fingerprint: firefox                  

- name: vmess-ws-$hostname                         
  type: vmess
  server: $vmadd_local                        
  port: $vm_port                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: $tls
  network: ws
  servername: $vm_name                    
  ws-opts:
    path: "$ws_path"                             
    headers:
      Host: $vm_name                     

- name: hysteria2-$hostname                            
  type: hysteria2                                      
  server: $cl_hy2_ip                               
  port: $hy2_port                                
  password: $uuid                          
  alpn:
    - h3
  sni: $hy2_name                               
  skip-cert-verify: $hy2_ins
  fast-open: true

- name: tuic5-$hostname                            
  server: $cl_tu5_ip                      
  port: $tu5_port                                    
  type: tuic
  uuid: $uuid       
  password: $uuid   
  alpn: [h3]
  disable-sni: true
  reduce-rtt: true
  udp-relay-mode: native
  congestion-controller: bbr
  sni: $tu5_name                                
  skip-cert-verify: $tu5_ins

- name: anytls-$hostname
  type: anytls
  server: $server_ipcl
  port: $anytls_port
  password: $uuid
  sni: $vl_name
  client-fingerprint: firefox
  reality-opts:
    public-key: $public_key
    short-id: $short_id

proxy-groups:
- name: 負載均衡
  type: load-balance
  url: https://www.gstatic.com/generate_204
  interval: 300
  strategy: round-robin
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    - anytls-$hostname

- name: 自動選擇
  type: url-test
  url: https://www.gstatic.com/generate_204
  interval: 300
  tolerance: 50
  proxies:
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    - anytls-$hostname
    
- name: 🌍選擇代理節點
  type: select
  proxies:
    - 負載均衡                                         
    - 自動選擇
    - DIRECT
    - vless-reality-vision-$hostname                              
    - vmess-ws-$hostname
    - hysteria2-$hostname
    - tuic5-$hostname
    - anytls-$hostname
rules:
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,🌍選擇代理節點
EOF
fi

cat > /etc/s-box/v2rayn_hy2.yaml <<EOF
server: $sb_hy2_ip:$hy2_port
auth: $uuid
tls:
  sni: $hy2_name
  insecure: $hy2_ins
fastOpen: true
socks5:
  listen: 127.0.0.1:50000
lazy: true
transport:
  udp:
    hopInterval: 30s
EOF

cat > /etc/s-box/v2rayn_tu5.json <<EOF
{
    "relay": {
        "server": "$sb_tu5_ip:$tu5_port",
        "uuid": "$uuid",
        "password": "$uuid",
        "congestion_control": "bbr",
        "alpn": ["h3", "spdy/3.1"]
    },
    "local": {
        "server": "127.0.0.1:55555"
    },
    "log_level": "info"
}
EOF
if [[ -n $hy2_ports ]]; then
hy2_ports=",$hy2_ports"
hy2_ports=$(echo $hy2_ports | sed 's/:/-/g')
a=$hy2_ports
sed -i "/server:/ s/$/$a/" /etc/s-box/v2rayn_hy2.yaml
fi
sed -i 's/server: \(.*\)/server: "\1"/' /etc/s-box/v2rayn_hy2.yaml
}

cfargo_ym(){
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
if [[ "$tls" = "false" ]]; then
echo
yellow "1：Argo臨時隧道"
yellow "2：Argo固定隧道"
yellow "0：返回上層"
readp "請選擇【0-2】：" menu
if [ "$menu" = "1" ]; then
cfargo
elif [ "$menu" = "2" ]; then
cfargoym
else
changeserv
fi
else
yellow "因vmess開啓了tls，Argo隧道功能不可用" && sleep 2
fi
}

cloudflaredargo(){
if [ ! -e /etc/s-box/cloudflared ]; then
case $(uname -m) in
aarch64) cpu=arm64;;
x86_64) cpu=amd64;;
esac
curl -L -o /etc/s-box/cloudflared -# --retry 2 https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cpu
#curl -L -o /etc/s-box/cloudflared -# --retry 2 https://gitlab.com/rwkgyg/sing-box-yg/-/raw/main/$cpu
chmod +x /etc/s-box/cloudflared
fi
}

cfargoym(){
echo
if [[ -f /etc/s-box/sbargotoken.log && -f /etc/s-box/sbargoym.log ]]; then
green "當前Argo固定隧道域名：$(cat /etc/s-box/sbargoym.log 2>/dev/null)"
green "當前Argo固定隧道Token：$(cat /etc/s-box/sbargotoken.log 2>/dev/null)"
fi
echo
green "請確保Cloudflare官網 --- Zero Trust --- Networks --- Tunnels已設置完成"
yellow "1：重置/設置Argo固定隧道域名"
yellow "2：停止Argo固定隧道"
yellow "0：返回上層"
readp "請選擇【0-2】：" menu
if [ "$menu" = "1" ]; then
cloudflaredargo
readp "輸入Argo固定隧道Token: " argotoken
readp "輸入Argo固定隧道域名: " argoym
if [[ -n $(ps -e | grep cloudflared) ]]; then
kill -15 $(cat /etc/s-box/sbargoympid.log 2>/dev/null) >/dev/null 2>&1
fi
echo
if [[ -n "${argotoken}" && -n "${argoym}" ]]; then
nohup setsid /etc/s-box/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token ${argotoken} >/dev/null 2>&1 & echo "$!" > /etc/s-box/sbargoympid.log
sleep 20
fi
echo ${argoym} > /etc/s-box/sbargoym.log
echo ${argotoken} > /etc/s-box/sbargotoken.log
crontab -l > /tmp/crontab.tmp
sed -i '/sbargoympid/d' /tmp/crontab.tmp
echo '@reboot sleep 10 && /bin/bash -c "nohup setsid /etc/s-box/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token $(cat /etc/s-box/sbargotoken.log 2>/dev/null) >/dev/null 2>&1 & pid=\$! && echo \$pid > /etc/s-box/sbargoympid.log"' >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
argo=$(cat /etc/s-box/sbargoym.log 2>/dev/null)
blue "Argo固定隧道設置完成，固定域名：$argo"
elif [ "$menu" = "2" ]; then
kill -15 $(cat /etc/s-box/sbargoympid.log 2>/dev/null) >/dev/null 2>&1
crontab -l > /tmp/crontab.tmp
sed -i '/sbargoympid/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
rm -rf /etc/s-box/vm_ws_argogd.txt
green "Argo固定隧道已停止"
else
cfargo_ym
fi
}

cfargo(){
echo
yellow "1：重置Argo臨時隧道域名"
yellow "2：停止Argo臨時隧道"
yellow "0：返回上層"
readp "請選擇【0-2】：" menu
if [ "$menu" = "1" ]; then
cloudflaredargo
i=0
while [ $i -le 4 ]; do let i++
yellow "第$i次刷新驗證Cloudflared Argo臨時隧道域名有效性，請稍等……"
if [[ -n $(ps -e | grep cloudflared) ]]; then
kill -15 $(cat /etc/s-box/sbargopid.log 2>/dev/null) >/dev/null 2>&1
fi
nohup setsid /etc/s-box/cloudflared tunnel --url http://localhost:$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port') --edge-ip-version auto --no-autoupdate --protocol http2 > /etc/s-box/argo.log 2>&1 &
echo "$!" > /etc/s-box/sbargopid.log
sleep 20
if [[ -n $(curl -sL https://$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')/ -I | awk 'NR==1 && /404|400|503/') ]]; then
argo=$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
blue "Argo臨時隧道申請成功，域名驗證有效：$argo" && sleep 2
break
fi
if [ $i -eq 5 ]; then
echo
yellow "Argo臨時域名驗證暫不可用，稍後可能會自動恢復，或者申請重置" && sleep 3
fi
done
crontab -l > /tmp/crontab.tmp
sed -i '/sbargopid/d' /tmp/crontab.tmp
echo '@reboot sleep 10 && /bin/bash -c "nohup setsid /etc/s-box/cloudflared tunnel --url http://localhost:$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port') --edge-ip-version auto --no-autoupdate --protocol http2 > /etc/s-box/argo.log 2>&1 & pid=\$! && echo \$pid > /etc/s-box/sbargopid.log"' >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
elif [ "$menu" = "2" ]; then
kill -15 $(cat /etc/s-box/sbargopid.log 2>/dev/null) >/dev/null 2>&1
crontab -l > /tmp/crontab.tmp
sed -i '/sbargopid/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
rm -rf /etc/s-box/vm_ws_argols.txt
green "Argo臨時隧道已停止"
else
cfargo_ym
fi
}

instsllsingbox(){
if [[ -f '/etc/systemd/system/sing-box.service' ]]; then
red "已安裝Sing-box服務，無法再次安裝" && exit
fi
mkdir -p /etc/s-box
v6
openyn
inssb
inscertificate
insport
sleep 2
echo
blue "Vless-reality相關key與id將自動生成……"
key_pair=$(/etc/s-box/sing-box generate reality-keypair)
private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
echo "$public_key" > /etc/s-box/public.key
short_id=$(/etc/s-box/sing-box generate rand --hex 4)
wget -q -O /root/geoip.db https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.db
wget -q -O /root/geosite.db https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.db
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "五、自動生成warp-wireguard出站賬戶" && sleep 2
warpwg
inssbjsonser
sbservice
sbactive
#curl -sL https://gitlab.com/rwkgyg/sing-box-yg/-/raw/main/version/version | awk -F "更新內容" '{print $1}' | head -n 1 > /etc/s-box/v
curl -sL https://raw.githubusercontent.com/yat-muk/sing-box-yg/main/version | awk -F "更新內容" '{print $1}' | head -n 1 > /etc/s-box/v
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
lnsb && blue "Sing-box-yg腳本安裝成功，腳本快捷方式：sb" && cronsb
echo
wgcfgo
sbshare
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
blue "Hysteria2/Tuic5自定義V2rayN配置、Clash-Meta/Sing-box客戶端配置及私有訂閱鏈接，請選擇9查看"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

changeym(){
[ -f /root/ygkkkca/ca.log ] && ymzs="$yellow切換為域名證書：$(cat /root/ygkkkca/ca.log 2>/dev/null)$plain" || ymzs="$yellow未申請域名證書，無法切換$plain"
vl_na="正在使用的域名：$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '(.inbounds[] | select(.tag == "vless-sb") | .tls.server_name)')。$yellow更換符合reality要求的域名，不支持證書域名$plain"
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '(.inbounds[] | select(.tag == "vmess-sb") | .tls.enabled)')
[[ "$tls" = "false" ]] && vm_na="當前已關閉TLS。$ymzs ${yellow}將開啓TLS，Argo隧道將不支持開啓${plain}" || vm_na="正在使用的域名證書：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellow切換為關閉TLS，Argo隧道將可用$plain"
hy2_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '(.inbounds[] | select(.tag == "hy2-sb") | .tls.key_path)')
[[ "$hy2_sniname" = '/etc/s-box/private.key' ]] && hy2_na="正在使用自簽bing證書。$ymzs" || hy2_na="正在使用的域名證書：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellow切換為自簽bing證書$plain"
tu5_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '(.inbounds[] | select(.tag == "tuic5-sb") | .tls.key_path)')
[[ "$tu5_sniname" = '/etc/s-box/private.key' ]] && tu5_na="正在使用自簽bing證書。$ymzs" || tu5_na="正在使用的域名證書：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellow切換為自簽bing證書$plain"
echo

# --- JQ 核心修復 ---
# 創建一個輔助函數來安全地更新所有 JSON 檔案
_safe_jq_update() {
    local query="$1"
    local success=true
    
    for file in $sbfiles; do
        if [[ ! -f "$file" ]]; then continue; fi
        
        jq "$query" "$file" > "$file.tmp"
        
        if [[ $? -ne 0 || ! -s "$file.tmp" ]]; then
            red "jq 處理 $file 失敗！"
            rm -f "$file.tmp"
            success=false
        else
            mv "$file.tmp" "$file"
        fi
    done
    
    if [[ "$success" = false ]]; then
        red "配置更新失敗，請檢查 jq 是否已安裝。"
        readp "按任意鍵返回..." key
        sb
        return 1
    fi
    return 0
}
# --- JQ 修復結束 ---

green "請選擇要切換證書模式的協議"
green "1：vless-reality協議，$vl_na"
if [[ -f /root/ygkkkca/ca.log ]]; then
green "2：vmess-ws協議，$vm_na"
green "3：Hysteria2協議，$hy2_na"
green "4：Tuic5協議，$tu5_na"
else
red "僅支持選項1 (vless-reality)。因未申請域名證書，vmess-ws、Hysteria-2、Tuic-v5的證書切換選項暫不予顯示"
fi
green "0：返回上層"
readp "請選擇：" menu
if [ "$menu" = "1" ]; then
    readp "請輸入vless-reality域名 (回車使用www.apple.com)：" menu
    ym_vl_re=${menu:-www.apple.com}
    
    # 構建 jq 查詢，同時更新 VLESS 和 AnyTLS 的 SNI 和 handshake server
    local query
    query='(.inbounds[] | select(.tag == "vless-sb") | .tls.server_name) = "'"$ym_vl_re"'"'
    query+=' | (.inbounds[] | select(.tag == "vless-sb") | .tls.reality.handshake.server) = "'"$ym_vl_re"'"'
    query+=' | (.inbounds[] | select(.tag == "anytls-sb") | .tls.server_name) = "'"$ym_vl_re"'"'
    query+=' | (.inbounds[] | select(.tag == "anytls-sb") | .tls.reality.handshake.server) = "'"$ym_vl_re"'"'
    
    _safe_jq_update "$query"
    
    restartsb
    blue "設置完畢，請回到主菜單進入選項9更新節點配置"

elif [ "$menu" = "2" ]; then
    if [ -f /root/ygkkkca/ca.log ]; then
        a=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
        [ "$a" = "true" ] && a_a=false || a_a=true
        b=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.server_name')
        [ "$b" = "www.bing.com" ] && b_b=$(cat /root/ygkkkca/ca.log) || b_b=$(cat /root/ygkkkca/ca.log)
        c=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.certificate_path')
        d=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.key_path')
        if [ "$d" = '/etc/s-box/private.key' ]; then
            c_c='/root/ygkkkca/cert.crt'
            d_d='/root/ygkkkca/private.key'
        else
            c_c='/etc/s-box/cert.pem'
            d_d='/etc/s-box/private.key'
        fi
        
        # 構建 Vmess 的 jq 查詢
        local query
        query='(.inbounds[] | select(.tag == "vmess-sb") | .tls.enabled) = '"$a_a"
        query+=' | (.inbounds[] | select(.tag == "vmess-sb") | .tls.server_name) = "'"$b_b"'"'
        query+=' | (.inbounds[] | select(.tag == "vmess-sb") | .tls.certificate_path) = "'"$c_c"'"'
        query+=' | (.inbounds[] | select(.tag == "vmess-sb") | .tls.key_path) = "'"$d_d"'"'
        
        _safe_jq_update "$query"
        
        restartsb
        blue "設置完畢，請回到主菜單進入選項9更新節點配置"
        echo
        tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
        vm_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port')
        blue "當前Vmess-ws(tls)的端口：$vm_port"
        [[ "$tls" = "false" ]] && blue "切記：可進入主菜單選項4-2，將Vmess-ws端口更改為任意7個80系端口(80、8080、8880、2052、2082、2086、2095)，可實現CDN優選IP" || blue "切記：可進入主菜單選項4-2，將Vmess-ws-tls端口更改為任意6個443系的端口(443、8443、2053、2083、2087、2096)，可實現CDN優選IP"
        echo
    else
        red "當前未申請域名證書，不可切換。主菜單選擇12，執行Acme證書申請" && sleep 2 && sb
    fi

elif [ "$menu" = "3" ]; then
    if [ -f /root/ygkkkca/ca.log ]; then
        c=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].tls.certificate_path')
        d=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].tls.key_path')
        if [ "$d" = '/etc/s-box/private.key' ]; then
            c_c='/root/ygkkkca/cert.crt'
            d_d='/root/ygkkkca/private.key'
        else
            c_c='/etc/s-box/cert.pem'
            d_d='/etc/s-box/private.key'
        fi
        
        # 構建 Hysteria2 的 jq 查詢
        local query
        query='(.inbounds[] | select(.tag == "hy2-sb") | .tls.certificate_path) = "'"$c_c"'"'
        query+=' | (.inbounds[] | select(.tag == "hy2-sb") | .tls.key_path) = "'"$d_d"'"'
        
        _safe_jq_update "$query"
        
        restartsb
        blue "設置完畢，請回到主菜單進入選項9更新節點配置"
    else
        red "當前未申請域名證書，不可切換。主菜單選擇12，執行Acme證書申請" && sleep 2 && sb
    fi

elif [ "$menu" = "4" ]; then
    if [ -f /root/ygkkkca/ca.log ]; then
        c=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.certificate_path')
        d=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.key_path')
        if [ "$d" = '/etc/s-box/private.key' ]; then
            c_c='/root/ygkkkca/cert.crt'
            d_d='/root/ygkkkca/private.key'
        else
            c_c='/etc/s-box/cert.pem'
            d_d='/etc/s-box/private.key'
        fi
        
        # 構建 Tuic5 的 jq 查詢
        local query
        query='(.inbounds[] | select(.tag == "tuic5-sb") | .tls.certificate_path) = "'"$c_c"'"'
        query+=' | (.inbounds[] | select(.tag == "tuic5-sb") | .tls.key_path) = "'"$d_d"'"'
        
        _safe_jq_update "$query"

        restartsb
        blue "設置完畢，請回到主菜單進入選項9更新節點配置"
    else
        red "當前未申請域名證書，不可切換。主菜單選擇12，執行Acme證書申請" && sleep 2 && sb
    fi
else
    sb
fi
}

allports(){
vl_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].listen_port')
vm_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port')
hy2_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].listen_port')
tu5_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].listen_port')
hy2_ports=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$hy2_port" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ',' | sed 's/,$//')
tu5_ports=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$tu5_port" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ',' | sed 's/,$//')
anytls_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[4].listen_port')
[[ -n $hy2_ports ]] && hy2zfport="$hy2_ports" || hy2zfport="未添加"
[[ -n $tu5_ports ]] && tu5zfport="$tu5_ports" || tu5zfport="未添加"
}

changeport(){
sbactive
allports
fports(){
readp "\n請輸入轉發的端口範圍 (1000-65535範圍內，格式為 小數字:大數字)：" rangeport
if [[ $rangeport =~ ^([1-9][0-9]{3,4}:[1-9][0-9]{3,4})$ ]]; then
b=${rangeport%%:*}
c=${rangeport##*:}
if [[ $b -ge 1000 && $b -le 65535 && $c -ge 1000 && $c -le 65535 && $b -lt $c ]]; then
iptables -t nat -A PREROUTING -p udp --dport $rangeport -j DNAT --to-destination :$port
ip6tables -t nat -A PREROUTING -p udp --dport $rangeport -j DNAT --to-destination :$port
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
blue "已確認轉發的端口範圍：$rangeport"
else
red "輸入的端口範圍不在有效範圍內" && fports
fi
else
red "輸入格式不正確。格式為 小數字:大數字" && fports
fi
echo
}
fport(){
readp "\n請輸入一個轉發的端口 (1000-65535範圍內)：" onlyport
if [[ $onlyport -ge 1000 && $onlyport -le 65535 ]]; then
iptables -t nat -A PREROUTING -p udp --dport $onlyport -j DNAT --to-destination :$port
ip6tables -t nat -A PREROUTING -p udp --dport $onlyport -j DNAT --to-destination :$port
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
blue "已確認轉發的端口：$onlyport"
else
blue "輸入的端口不在有效範圍內" && fport
fi
echo
}

hy2deports(){
allports
hy2_ports=$(echo "$hy2_ports" | sed 's/,/,/g')
IFS=',' read -ra ports <<< "$hy2_ports"
for port in "${ports[@]}"; do
iptables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$hy2_port
ip6tables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$hy2_port
done
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
}
tu5deports(){
allports
tu5_ports=$(echo "$tu5_ports" | sed 's/,/,/g')
IFS=',' read -ra ports <<< "$tu5_ports"
for port in "${ports[@]}"; do
iptables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$tu5_port
ip6tables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$tu5_port
done
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
}

# --- JQ 核心修復 ---
# 創建一個輔助函數來安全地更新所有 JSON 檔案
safe_jq_update() {
    local tag="$1"
    local new_port="$2"
    local success=true
    
    # $sbfiles 變數包含 sb10.json, sb11.json, 和 sb.json
    for file in $sbfiles; do
        if [[ ! -f "$file" ]]; then
            yellow "警告: 配置文件 $file 不存在，跳過..."
            continue
        fi
        
        # 使用 jq 精確修改 'listen_port'，基於 'tag'
        # 注意: $new_port 是一個數字，所以在 jq 中不需要引號
        jq '(.inbounds[] | select(.tag == "'"$tag"'") | .listen_port) = '"$new_port"'' "$file" > "$file.tmp"
        
        if [[ $? -ne 0 || ! -s "$file.tmp" ]]; then
            red "jq 處理 $file 失敗！"
            rm -f "$file.tmp"
            success=false
        else
            mv "$file.tmp" "$file"
        fi
    done
    
    if [[ "$success" = false ]]; then
        red "配置更新失敗，請檢查 jq 是否已安裝。"
        return 1
    fi
    return 0
}
# --- JQ 修復結束 ---


allports
green "Vless-reality與Vmess-ws僅能更改唯一的端口，vmess-ws注意Argo端口重置"
green "Hysteria2與Tuic5支持更改主端口，也支持增刪多個轉發端口"
green "Hysteria2支持端口跳躍，且與Tuic5都支持多端口復用"
echo
green "1：Vless-reality協議 ${yellow}端口:$vl_port${plain}"
green "2：Vmess-ws協議 ${yellow}端口:$vm_port${plain}"
green "3：Hysteria2協議 ${yellow}端口:$hy2_port  轉發多端口: $hy2zfport${plain}"
green "4：Tuic5協議 ${yellow}端口:$tu5_port  轉發多端口: $tu5zfport${plain}"
green "5：AnyTLS協議 ${yellow}端口:$anytls_port${plain}"
green "0：返回上層"
readp "請選擇要變更端口的協議【0-5】：" menu

if [ "$menu" = "1" ]; then
    vlport # 獲取 $port_vl_re
    safe_jq_update "vless-sb" "$port_vl_re" || (sleep 2 && sb)
    restartsb
    blue "Vless-reality端口更改完成，可選擇9輸出配置信息"
    echo

elif [ "$menu" = "2" ]; then
    vmport # 獲取 $port_vm_ws
    safe_jq_update "vmess-sb" "$port_vm_ws" || (sleep 2 && sb)
    restartsb
    blue "Vmess-ws端口更改完成，可選擇9輸出配置信息"
    tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
    if [[ "$tls" = "false" ]]; then
        blue "切記：如果Argo使用中，臨時隧道必須重置，固定隧道的CF設置界面端口必須修改為$port_vm_ws"
    else
        blue "當前Argo隧道已不支持開啓"
    fi
    echo

elif [ "$menu" = "3" ]; then
    green "1：更換Hysteria2主端口 (原多端口自動重置刪除)"
    green "2：添加Hysteria2多端口"
    green "3：重置刪除Hysteria2多端口"
    green "0：返回上層"
    readp "請選擇【0-3】：" menu
    if [ "$menu" = "1" ]; then
        if [ -n $hy2_ports ]; then hy2deports; fi
        hy2port # 獲取 $port_hy2
        safe_jq_update "hy2-sb" "$port_hy2" || (sleep 2 && sb)
        restartsb
        result_vl_vm_hy_tu && reshy2 && sb_client
    elif [ "$menu" = "2" ]; then
        green "1：添加Hysteria2範圍端口"
        green "2：添加Hysteria2單端口"
        green "0：返回上層"
        readp "請選擇【0-2】：" menu
        if [ "$menu" = "1" ]; then
            port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].listen_port')
            fports && result_vl_vm_hy_tu && sb_client && changeport
        elif [ "$menu" = "2" ]; then
            port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].listen_port')
            fport && result_vl_vm_hy_tu && sb_client && changeport
        else
            changeport
        fi
    elif [ "$menu" = "3" ]; then
        if [ -n $hy2_ports ]; then
            hy2deports && result_vl_vm_hy_tu && sb_client && changeport
        else
            yellow "Hysteria2未設置多端口" && changeport
        fi
    else
        changeport
    fi

elif [ "$menu" = "4" ]; then
    green "1：更換Tuic5主端口 (原多端口自動重置刪除)"
    green "2：添加Tuic5多端口"
    green "3：重置刪除Tuic5多端口"
    green "0：返回上層"
    readp "請選擇【0-3】：" menu
    if [ "$menu" = "1" ]; then
        if [ -n $tu5_ports ]; then tu5deports; fi
        tu5port # 獲取 $port_tu
        safe_jq_update "tuic5-sb" "$port_tu" || (sleep 2 && sb)
        restartsb
        result_vl_vm_hy_tu && restu5 && sb_client
    elif [ "$menu" = "2" ]; then
        green "1：添加Tuic5範圍端口"
        green "2：添加Tuic5單端口"
        green "0：返回上層"
        readp "請選擇【0-2】：" menu
        if [ "$menu" = "1" ]; then
            port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].listen_port')
            fports && result_vl_vm_hy_tu && sb_client && changeport
        elif [ "$menu" = "2" ]; then
            port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inS[3].listen_port')
            fport && result_vl_vm_hy_tu && sb_client && changeport
        else
            changeport
        fi
    elif [ "$menu" = "3" ]; then
        if [ -n $tu5_ports ]; then
            tu5deports && result_vl_vm_hy_tu && sb_client && changeport
        else
            yellow "Tuic5未設置多端口" && changeport
        fi
    else
        changeport
    fi

elif [ "$menu" = "5" ]; then
    anytlsport # 獲取 $port_anytls
    safe_jq_update "anytls-sb" "$port_anytls" || (sleep 2 && sb)
    restartsb
    blue "AnyTLS端口更改完成，可選擇9輸出配置信息"
    echo

else
    sb
fi
}

changeuuid(){
echo
olduuid=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '(.inbounds[] | select(.tag == "vless-sb") | .users[0].uuid)')
oldvmpath=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '(.inbounds[] | select(.tag == "vmess-sb") | .transport.path)')
green "全協議的uuid (密碼)：$olduuid"
green "Vmess的path路徑：$oldvmpath"
echo

# --- JQ 核心修復 ---
# 創建一個輔助函數來安全地更新所有 JSON 檔案
safe_jq_update() {
    local query="$1"
    local success=true
    
    # $sbfiles 變數包含 sb10.json, sb11.json, 和 sb.json
    for file in $sbfiles; do
        if [[ ! -f "$file" ]]; then
            yellow "警告: 配置文件 $file 不存在，跳過..."
            continue
        fi
        
        # 使用 jq 精確修改
        jq "$query" "$file" > "$file.tmp"
        
        if [[ $? -ne 0 || ! -s "$file.tmp" ]]; then
            red "jq 處理 $file 失敗！"
            rm -f "$file.tmp"
            success=false
        else
            mv "$file.tmp" "$file"
        fi
    done
    
    if [[ "$success" = false ]]; then
        red "配置更新失敗，請檢查 jq 是否已安裝。"
        readp "按任意鍵返回..." key
        sb
        return 1
    fi
    return 0
}
# --- JQ 修復結束 ---

yellow "1：自定義全協議的uuid (密碼)"
yellow "2：自定義Vmess的path路徑"
yellow "0：返回上層"
readp "請選擇【0-2】：" menu
if [ "$menu" = "1" ]; then
    readp "輸入uuid，必須是uuid格式，不懂就回車(重置並隨機生成uuid)：" menu
    if [ -z "$menu" ]; then
        uuid=$(/etc/s-box/sing-box generate uuid)
    else
        uuid=$menu
    fi

    # 構建一個組合的 jq 查詢，精確更新所有協議的密碼/uuid
    local query_uuid
    query_uuid='(.inbounds[] | select(.tag == "vless-sb") | .users[0].uuid) = "'"$uuid"'"'
    query_uuid+=' | (.inbounds[] | select(.tag == "vmess-sb") | .users[0].uuid) = "'"$uuid"'"'
    query_uuid+=' | (.inbounds[] | select(.tag == "hy2-sb") | .users[0].password) = "'"$uuid"'"'
    query_uuid+=' | (.inbounds[] | select(.tag == "tuic5-sb") | .users[0].uuid) = "'"$uuid"'"'
    query_uuid+=' | (.inbounds[] | select(.tag == "tuic5-sb") | .users[0].password) = "'"$uuid"'"'
    query_uuid+=' | (.inbounds[] | select(.tag == "anytls-sb") | .users[0].password) = "'"$uuid"'"'

    safe_jq_update "$query_uuid"
    
    restartsb
    blue "已確認uuid (密碼)：${uuid}" 
    blue "已確認Vmess的path路徑：$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '(.inbounds[] | select(.tag == "vmess-sb") | .transport.path)')"

elif [ "$menu" = "2" ]; then
    readp "輸入Vmess的path路徑，回車表示不變：" menu
    if [ -z "$menu" ]; then
        echo
    else
        vmpath=$menu
        # 精確更新 Vmess 的 path
        local query_path
        query_path='(.inbounds[] | select(.tag == "vmess-sb") | .transport.path) = "'"$vmpath"'"'
        
        safe_jq_update "$query_path"
        restartsb
    fi
    blue "已確認Vmess的path路徑：$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '(.inbounds[] | select(.tag == "vmess-sb") | .transport.path)')"
    sbshare
else
    changeserv
fi
}

changeip(){
v4v6
chip(){
    # rpip 變數不再需要，jq 可以直接修改
    [[ "$sbnh" == "1.10" ]] && num=10 || num=11

    # === JQ 修復 (不再使用 sed 或行號) ===
    
    # 1. 修正 sb10.json
    # 使用 jq 尋找 .outbounds 數組中 "tag" == "direct" 的對象，並將其 "domain_strategy" 設置為新的 $rrpip 值
    jq '(.outbounds[] | select(.tag == "direct") | .domain_strategy) = "'"$rrpip"'"' /etc/s-box/sb10.json > /etc/s-box/sb10.json.tmp
    
    # 檢查 jq 是否成功執行
    if [[ $? -ne 0 || ! -s /etc/s-box/sb10.json.tmp ]]; then
        red "jq 處理 /etc/s-box/sb10.json 失敗！"
        red "請確保 jq 已正確安裝。"
        rm -f /etc/s-box/sb10.json.tmp
        readp "按任意鍵返回..." key
        sb
        return 1
    fi
    # 替換原檔案
    mv /etc/s-box/sb10.json.tmp /etc/s-box/sb10.json

    # 2. 修正 sb11.json
    jq '(.outbounds[] | select(.tag == "direct") | .domain_strategy) = "'"$rrpip"'"' /etc/s-box/sb11.json > /etc/s-box/sb11.json.tmp
    
    if [[ $? -ne 0 || ! -s /etc/s-box/sb11.json.tmp ]]; then
        red "jq 處理 /etc/s-box/sb11.json 失敗！"
        red "請確保 jq 已正確安裝。"
        rm -f /etc/s-box/sb11.json.tmp
        readp "按任意鍵返回..." key
        sb
        return 1
    fi
    mv /etc/s-box/sb11.json.tmp /etc/s-box/sb11.json

    # 3. 應用更改
    rm -rf /etc/s-box/sb.json
    cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
    restartsb
}
readp "1. IPV4優先\n2. IPV6優先\n3. 僅IPV4\n4. 僅IPV6\n请选择：" choose
if [[ $choose == "1" && -n $v4 ]]; then
rrpip="prefer_ipv4" && chip && v4_6="IPV4優先($v4)"
elif [[ $choose == "2" && -n $v6 ]]; then
rrpip="prefer_ipv6" && chip && v4_6="IPV6優先($v6)"
elif [[ $choose == "3" && -n $v4 ]]; then
rrpip="ipv4_only" && chip && v4_6="僅IPV4($v4)"
elif [[ $choose == "4" && -n $v6 ]]; then
rrpip="ipv6_only" && chip && v4_6="僅IPV6($v6)"
else 
red "當前不存在你選擇的IPV4/IPV6地址，或者輸入錯誤" && changeip
fi
blue "當前已更換的IP優先級：${v4_6}" && sb
}

tgsbshow(){
echo
yellow "1：重置/設置Telegram機器人的Token、用戶ID"
yellow "0：返回上層"
readp "請選擇【0-1】：" menu
if [ "$menu" = "1" ]; then
rm -rf /etc/s-box/sbtg.sh
readp "輸入Telegram機器人Token: " token
telegram_token=$token
readp "輸入Telegram機器人用戶ID: " userid
telegram_id=$userid
echo '#!/bin/bash
export LANG=en_US.UTF-8

total_lines=$(wc -l < /etc/s-box/clash_meta_client.yaml)
half=$((total_lines / 2))
head -n $half /etc/s-box/clash_meta_client.yaml > /etc/s-box/clash_meta_client1.txt
tail -n +$((half + 1)) /etc/s-box/clash_meta_client.yaml > /etc/s-box/clash_meta_client2.txt

total_lines=$(wc -l < /etc/s-box/sing_box_client.json)
quarter=$((total_lines / 4))
head -n $quarter /etc/s-box/sing_box_client.json > /etc/s-box/sing_box_client1.txt
tail -n +$((quarter + 1)) /etc/s-box/sing_box_client.json | head -n $quarter > /etc/s-box/sing_box_client2.txt
tail -n +$((2 * quarter + 1)) /etc/s-box/sing_box_client.json | head -n $quarter > /etc/s-box/sing_box_client3.txt
tail -n +$((3 * quarter + 1)) /etc/s-box/sing_box_client.json > /etc/s-box/sing_box_client4.txt

m1=$(cat /etc/s-box/vl_reality.txt 2>/dev/null)
m2=$(cat /etc/s-box/vm_ws.txt 2>/dev/null)
m3=$(cat /etc/s-box/vm_ws_argols.txt 2>/dev/null)
m3_5=$(cat /etc/s-box/vm_ws_argogd.txt 2>/dev/null)
m4=$(cat /etc/s-box/vm_ws_tls.txt 2>/dev/null)
m5=$(cat /etc/s-box/hy2.txt 2>/dev/null)
m6=$(cat /etc/s-box/tuic5.txt 2>/dev/null)
m7=$(cat /etc/s-box/sing_box_client1.txt 2>/dev/null)
m7_5=$(cat /etc/s-box/sing_box_client2.txt 2>/dev/null)
m7_5_5=$(cat /etc/s-box/sing_box_client3.txt 2>/dev/null)
m7_5_5_5=$(cat /etc/s-box/sing_box_client4.txt 2>/dev/null)
m8=$(cat /etc/s-box/clash_meta_client1.txt 2>/dev/null)
m8_5=$(cat /etc/s-box/clash_meta_client2.txt 2>/dev/null)
m9=$(cat /etc/s-box/sing_box_gitlab.txt 2>/dev/null)
m10=$(cat /etc/s-box/clash_meta_gitlab.txt 2>/dev/null)
m11=$(cat /etc/s-box/jh_sub.txt 2>/dev/null)
message_text_m1=$(echo "$m1")
message_text_m2=$(echo "$m2")
message_text_m3=$(echo "$m3")
message_text_m3_5=$(echo "$m3_5")
message_text_m4=$(echo "$m4")
message_text_m5=$(echo "$m5")
message_text_m6=$(echo "$m6")
message_text_m7=$(echo "$m7")
message_text_m7_5=$(echo "$m7_5")
message_text_m7_5_5=$(echo "$m7_5_5")
message_text_m7_5_5_5=$(echo "$m7_5_5_5")
message_text_m8=$(echo "$m8")
message_text_m8_5=$(echo "$m8_5")
message_text_m9=$(echo "$m9")
message_text_m10=$(echo "$m10")
message_text_m11=$(echo "$m11")
MODE=HTML
URL="https://api.telegram.org/bottelegram_token/sendMessage"
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Vless-reality-vision 分享鏈接 】：支持nekobox "$'"'"'\n\n'"'"'"${message_text_m1}")
if [[ -f /etc/s-box/vm_ws.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Vmess-ws 分享鏈接 】：支持v2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m2}")
fi
if [[ -f /etc/s-box/vm_ws_argols.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Vmess-ws(tls)+Argo臨時域名分享鏈接 】：支持v2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m3}")
fi
if [[ -f /etc/s-box/vm_ws_argogd.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Vmess-ws(tls)+Argo固定域名分享鏈接 】：支持v2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m3_5}")
fi
if [[ -f /etc/s-box/vm_ws_tls.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Vmess-ws-tls 分享鏈接 】：支持v2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m4}")
fi
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Hysteria-2 分享鏈接 】：支持nekobox "$'"'"'\n\n'"'"'"${message_text_m5}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Tuic-v5 分享鏈接 】：支持nekobox "$'"'"'\n\n'"'"'"${message_text_m6}")

if [[ -f /etc/s-box/sing_box_gitlab.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Sing-box 訂閱鏈接 】：支持SFA、SFW、SFI "$'"'"'\n\n'"'"'"${message_text_m9}")
else
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Sing-box 配置文件(4段) 】：支持SFA、SFW、SFI "$'"'"'\n\n'"'"'"${message_text_m7}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m7_5}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m7_5_5}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m7_5_5_5}")
fi

if [[ -f /etc/s-box/clash_meta_gitlab.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Clash-meta 訂閱鏈接 】：支持Clash-meta相關客戶端 "$'"'"'\n\n'"'"'"${message_text_m10}")
else
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Clash-meta 配置文件(2段) 】：支持Clash-meta相關客戶端 "$'"'"'\n\n'"'"'"${message_text_m8}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m8_5}")
fi
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 四合一協議聚合訂閱鏈接 】：支持nekobox "$'"'"'\n\n'"'"'"${message_text_m11}")

if [ $? == 124 ];then
echo TG_api請求超時,請檢查網絡是否重啓完成並是否能夠訪問TG
fi
resSuccess=$(echo "$res" | jq -r ".ok")
if [[ $resSuccess = "true" ]]; then
echo "TG推送成功";
else
echo "TG推送失敗，請檢查TG機器人Token和ID";
fi
' > /etc/s-box/sbtg.sh
sed -i "s/telegram_token/$telegram_token/g" /etc/s-box/sbtg.sh
sed -i "s/telegram_id/$telegram_id/g" /etc/s-box/sbtg.sh
green "設置完成！請確保TG機器人已處於激活狀態！"
tgnotice
else
changeserv
fi
}

tgnotice(){
if [[ -f /etc/s-box/sbtg.sh ]]; then
green "請稍等5秒，TG機器人準備推送……"
sbshare > /dev/null 2>&1
bash /etc/s-box/sbtg.sh
else
yellow "未設置TG通知功能"
fi
exit
}

changeserv(){
sbactive
echo
green "Sing-box配置變更選擇如下:"
readp "1：更換Reality域名偽裝地址、切換自簽證書與Acme域名證書、開關TLS\n2：更換全協議UUID(密碼)、Vmess-Path路徑\n3：設置Argo臨時隧道、固定隧道\n4：切換IPV4或IPV6的代理優先級\n5：設置Telegram推送節點通知\n6：更換Warp-wireguard出站賬戶\n7：設置Gitlab訂閱分享鏈接\n8：設置所有Vmess節點的CDN優選地址\n0：返回上層\n請選擇【0-8】：" menu
if [ "$menu" = "1" ];then
changeym
elif [ "$menu" = "2" ];then
changeuuid
elif [ "$menu" = "3" ];then
cfargo_ym
elif [ "$menu" = "4" ];then
changeip
elif [ "$menu" = "5" ];then
tgsbshow
elif [ "$menu" = "6" ];then
changewg
elif [ "$menu" = "7" ];then
gitlabsub
elif [ "$menu" = "8" ];then
vmesscfadd
else 
sb
fi
}

vmesscfadd(){
echo
green "推薦使用穩定的世界大廠或組織的官方CDN域名作為CDN優選地址："
blue "www.visa.com.sg"
blue "www.wto.org"
blue "www.web.com"
echo
yellow "1：自定義Vmess-ws(tls)主協議節點的CDN優選地址"
yellow "2：針對選項1，重置客戶端host/sni域名(IP解析到CF上的域名)"
yellow "3：自定義Vmess-ws(tls)-Argo節點的CDN優選地址"
yellow "0：返回上層"
readp "請選擇【0-3】：" menu
if [ "$menu" = "1" ]; then
echo
green "請確保VPS的IP已解析到Cloudflare的域名上"
if [[ ! -f /etc/s-box/cfymjx.txt ]] 2>/dev/null; then
readp "輸入客戶端host/sni域名(IP解析到CF上的域名)：" menu
echo "$menu" > /etc/s-box/cfymjx.txt
fi
echo
readp "輸入自定義的優選IP/域名：" menu
echo "$menu" > /etc/s-box/cfvmadd_local.txt
green "設置成功，選擇主菜單9進行節點配置更新" && sleep 2 && vmesscfadd
elif  [ "$menu" = "2" ]; then
rm -rf /etc/s-box/cfymjx.txt
green "重置成功，可選擇1重新設置" && sleep 2 && vmesscfadd
elif  [ "$menu" = "3" ]; then
readp "輸入自定義的優選IP/域名：" menu
echo "$menu" > /etc/s-box/cfvmadd_argo.txt
green "設置成功，選擇主菜單9進行節點配置更新" && sleep 2 && vmesscfadd
else
changeserv
fi
}

gitlabsub(){
echo
green "請確保Gitlab官網上已建立項目，已開啓推送功能，已獲取訪問令牌"
yellow "1：重置/設置Gitlab訂閱鏈接"
yellow "0：返回上層"
readp "請選擇【0-1】：" menu
if [ "$menu" = "1" ]; then
cd /etc/s-box
readp "輸入登錄郵箱: " email
readp "輸入訪問令牌: " token
readp "輸入用戶名: " userid
readp "輸入項目名: " project
echo
green "多台VPS共用一個令牌及項目名，可創建多個分支訂閱鏈接"
green "回車跳過表示不新建，僅使用主分支main訂閱鏈接(首台VPS建議回車跳過)"
readp "新建分支名稱: " gitlabml
echo
if [[ -z "$gitlabml" ]]; then
gitlab_ml=''
git_sk=main
rm -rf /etc/s-box/gitlab_ml_ml
else
gitlab_ml=":${gitlabml}"
git_sk="${gitlabml}"
echo "${gitlab_ml}" > /etc/s-box/gitlab_ml_ml
fi
echo "$token" > /etc/s-box/gitlabtoken.txt
rm -rf /etc/s-box/.git
git init >/dev/null 2>&1
git add sing_box_client.json clash_meta_client.yaml jh_sub.txt >/dev/null 2>&1
git config --global user.email "${email}" >/dev/null 2>&1
git config --global user.name "${userid}" >/dev/null 2>&1
git commit -m "commit_add_$(date +"%F %T")" >/dev/null 2>&1
branches=$(git branch)
if [[ $branches == *master* ]]; then
git branch -m master main >/dev/null 2>&1
fi
git remote add origin https://${token}@gitlab.com/${userid}/${project}.git >/dev/null 2>&1
if [[ $(ls -a | grep '^\.git$') ]]; then
cat > /etc/s-box/gitpush.sh <<EOF
#!/usr/bin/expect
spawn bash -c "git push -f origin main${gitlab_ml}"
expect "Password for 'https://$(cat /etc/s-box/gitlabtoken.txt 2>/dev/null)@gitlab.com':"
send "$(cat /etc/s-box/gitlabtoken.txt 2>/dev/null)\r"
interact
EOF
chmod +x gitpush.sh
./gitpush.sh "git push -f origin main${gitlab_ml}" cat /etc/s-box/gitlabtoken.txt >/dev/null 2>&1
echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/sing_box_client.json/raw?ref=${git_sk}&private_token=${token}" > /etc/s-box/sing_box_gitlab.txt
echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/clash_meta_client.yaml/raw?ref=${git_sk}&private_token=${token}" > /etc/s-box/clash_meta_gitlab.txt
echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/jh_sub.txt/raw?ref=${git_sk}&private_token=${token}" > /etc/s-box/jh_sub_gitlab.txt
clsbshow
else
yellow "設置Gitlab訂閱鏈接失敗，請反饋"
fi
cd
else
changeserv
fi
}

gitlabsubgo(){
cd /etc/s-box
if [[ $(ls -a | grep '^\.git$') ]]; then
if [ -f /etc/s-box/gitlab_ml_ml ]; then
gitlab_ml=$(cat /etc/s-box/gitlab_ml_ml)
fi
git rm --cached sing_box_client.json clash_meta_client.yaml jh_sub.txt >/dev/null 2>&1
git commit -m "commit_rm_$(date +"%F %T")" >/dev/null 2>&1
git add sing_box_client.json clash_meta_client.yaml jh_sub.txt >/dev/null 2>&1
git commit -m "commit_add_$(date +"%F %T")" >/dev/null 2>&1
chmod +x gitpush.sh
./gitpush.sh "git push -f origin main${gitlab_ml}" cat /etc/s-box/gitlabtoken.txt >/dev/null 2>&1
clsbshow
else
yellow "未設置Gitlab訂閱鏈接"
fi
cd
}

clsbshow(){
green "當前Sing-box節點已更新並推送"
green "Sing-box訂閱鏈接如下："
blue "$(cat /etc/s-box/sing_box_gitlab.txt 2>/dev/null)"
echo
green "Sing-box訂閱鏈接二維碼如下："
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/sing_box_gitlab.txt 2>/dev/null)"
echo
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
green "當前Clash-meta節點配置已更新並推送"
green "Clash-meta訂閱鏈接如下："
blue "$(cat /etc/s-box/clash_meta_gitlab.txt 2>/dev/null)"
echo
green "Clash-meta訂閱鏈接二維碼如下："
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/clash_meta_gitlab.txt 2>/dev/null)"
echo
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
green "當前聚合訂閱節點配置已更新並推送"
green "訂閱鏈接如下："
blue "$(cat /etc/s-box/jh_sub_gitlab.txt 2>/dev/null)"
echo
yellow "可以在網頁上輸入訂閱鏈接查看配置內容，如果無配置內容，請自檢Gitlab相關設置並重置"
echo
}

warpwg(){
warpcode(){
reg(){
keypair=$(openssl genpkey -algorithm X25519 | openssl pkey -text -noout)
private_key=$(echo "$keypair" | awk '/priv:/{flag=1; next} /pub:/{flag=0} flag' | tr -d '[:space:]' | xxd -r -p | base64)
public_key=$(echo "$keypair" | awk '/pub:/{flag=1} flag' | tr -d '[:space:]' | xxd -r -p | base64)
response=$(curl -sL --tlsv1.3 --connect-timeout 3 --max-time 5 \
-X POST 'https://api.cloudflareclient.com/v0a2158/reg' \
-H 'CF-Client-Version: a-7.21-0721' \
-H 'Content-Type: application/json' \
-d '{
"key": "'"$public_key"'",
"tos": "'"$(date -u +'%Y-%m-%dT%H:%M:%S.000Z')"'"
}')
if [ -z "$response" ]; then
return 1
fi
echo "$response" | python3 -m json.tool 2>/dev/null | sed "/\"account_type\"/i\         \"private_key\": \"$private_key\","
}
reserved(){
reserved_str=$(echo "$warp_info" | grep 'client_id' | cut -d\" -f4)
reserved_hex=$(echo "$reserved_str" | base64 -d | xxd -p)
reserved_dec=$(echo "$reserved_hex" | fold -w2 | while read HEX; do printf '%d ' "0x${HEX}"; done | awk '{print "["$1", "$2", "$3"]"}')
echo -e "{\n    \"reserved_dec\": $reserved_dec,"
echo -e "    \"reserved_hex\": \"0x$reserved_hex\","
echo -e "    \"reserved_str\": \"$reserved_str\"\n}"
}
result() {
echo "$warp_reserved" | grep -P "reserved" | sed "s/ //g" | sed 's/:"/: "/g' | sed 's/:\[/: \[/g' | sed 's/\([0-9]\+\),\([0-9]\+\),\([0-9]\+\)/\1, \2, \3/' | sed 's/^"/    "/g' | sed 's/"$/",/g'
echo "$warp_info" | grep -P "(private_key|public_key|\"v4\": \"172.16.0.2\"|\"v6\": \"2)" | sed "s/ //g" | sed 's/:"/: "/g' | sed 's/^"/    "/g'
echo "}"
}
warp_info=$(reg) 
warp_reserved=$(reserved) 
result
}
output=$(warpcode)
if ! echo "$output" 2>/dev/null | grep -w "private_key" > /dev/null; then
v6=2606:4700:110:860e:738f:b37:f15:d38d
pvk=g9I2sgUH6OCbIBTehkEfVEnuvInHYZvPOFhWchMLSc4=
res=[33,217,129]
else
pvk=$(echo "$output" | sed -n 4p | awk '{print $2}' | tr -d ' "' | sed 's/.$//')
v6=$(echo "$output" | sed -n 7p | awk '{print $2}' | tr -d ' "')
res=$(echo "$output" | sed -n 1p | awk -F":" '{print $NF}' | tr -d ' ' | sed 's/.$//')
fi
blue "Private_key私鑰：$pvk"
blue "IPV6地址：$v6"
blue "reserved值：$res"
}

changewg(){
[[ "$sbnh" == "1.10" ]] && num=10 || num=11

# --- JQ Read Operations ---
# Get current values from the active sb.json
if [[ "$sbnh" == "1.10" ]]; then
    # sb10.json structure
    wgprkey=$(jq -r '(.outbounds[] | select(.type == "wireguard") | .private_key)' /etc/s-box/sb.json)
    wgipv6=$(jq -r '(.outbounds[] | select(.type == "wireguard") | .local_address[1] | split("/")[0])' /etc/s-box/sb.json)
    wgres=$(jq -r '(.outbounds[] | select(.type == "wireguard") | .reserved)' /etc/s-box/sb.json)
    wgip=$(jq -r '(.outbounds[] | select(.type == "wireguard") | .server)' /etc/s-box/sb.json)
    wgpo=$(jq -r '(.outbounds[] | select(.type == "wireguard") | .server_port)' /etc/s-box/sb.json)
else
    # sb11.json structure
    wgprkey=$(jq -r '(.endpoints[] | select(.tag == "warp-out") | .private_key)' /etc/s-box/sb.json)
    wgipv6=$(jq -r '(.endpoints[] | select(.tag == "warp-out") | .address[1] | split("/")[0])' /etc/s-box/sb.json)
    wgres=$(jq -r '(.endpoints[] | select(.tag == "warp-out") | .peers[0].reserved)' /etc/s-box/sb.json)
    wgip=$(jq -r '(.endpoints[] | select(.tag == "warp-out") | .peers[0].address)' /etc/s-box/sb.json)
    wgpo=$(jq -r '(.endpoints[] | select(.tag == "warp-out") | .peers[0].port)' /etc/s-box/sb.json)
fi
# --- End JQ Read ---

echo
green "當前warp-wireguard可更換的參數如下："
green "Private_key私鑰：$wgprkey"
green "IPV6地址：$wgipv6"
green "Reserved值：$wgres" # jq -r prints 'null' if not present, which is fine
green "對端IP：$wgip:$wgpo"
echo
yellow "1：更換warp-wireguard賬戶"
yellow "2：(已修復) 優選Warp對端IP"
yellow "0：返回上層"
readp "請選擇【0-2】：" menu
if [ "$menu" = "1" ]; then
    green "最新隨機生成普通warp-wireguard賬戶如下"
    warpwg # This function provides $pvk, $v6, $res
    echo
    
    # Use the new values from warpwg ($pvk, $v6, $res)
    # If user provides custom values, overwrite them
    readp "輸入自定義Private_key (回車使用新生成的: $pvk)：" menu_pvk
    [[ -n "$menu_pvk" ]] && pvk="$menu_pvk"
    
    readp "輸入自定義IPV6地址 (回車使用新生成的: $v6)：" menu_v6
    [[ -n "$menu_v6" ]] && v6="$menu_v6"

    readp "輸入自定義Reserved值 (格式: [x,y,z]，回車使用新生成的: $res)：" menu_res
    [[ -n "$menu_res" ]] && res="$menu_res"

    # --- JQ Write Operations ---
    # Build queries for both sb10 and sb11
    
    # sb10 (v1.10)
    local query10
    query10='(.outbounds[] | select(.type == "wireguard") | .private_key) = "'"$pvk"'"'
    query10+=' | (.outbounds[] | select(.type == "wireguard") | .local_address[1]) = "'"$v6/128"'"'
    query10+=' | (.outbounds[] | select(.type == "wireguard") | .reserved) = '"$res"''
    
    # sb11 (v1.11+)
    local query11
    query11='(.endpoints[] | select(.tag == "warp-out") | .private_key) = "'"$pvk"'"'
    query11+=' | (.endpoints[] | select(.tag == "warp-out") | .address[1]) = "'"$v6/128"'"'
    query11+=' | (.endpoints[] | select(.tag == "warp-out") | .peers[0].reserved) = '"$res"''

    # Apply to sb10.json
    jq "$query10" /etc/s-box/sb10.json > /etc/s-box/sb10.json.tmp
    if [[ $? -ne 0 || ! -s /etc/s-box/sb10.json.tmp ]]; then
        red "jq 處理 sb10.json 失敗！" && rm -f /etc/s-box/sb10.json.tmp
    else
        mv /etc/s-box/sb10.json.tmp /etc/s-box/sb10.json
    fi
    
    # Apply to sb11.json
    jq "$query11" /etc/s-box/sb11.json > /etc/s-box/sb11.json.tmp
    if [[ $? -ne 0 || ! -s /etc/s-box/sb11.json.tmp ]]; then
        red "jq 處理 sb11.json 失敗！" && rm -f /etc/s-box/sb11.json.tmp
    else
        mv /etc/s-box/sb11.json.tmp /etc/s-box/sb11.json
    fi
    # --- End JQ Write ---

    rm -rf /etc/s-box/sb.json
    cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
    restartsb
    green "設置結束"
    green "可以先在選項5-1或5-2使用完整域名分流：cloudflare.com"
    green "然後使用任意節點打開網頁https://cloudflare.com/cdn-cgi/trace，查看當前WARP賬戶類型"

elif  [ "$menu" = "2" ]; then
    green "請稍等……更新中……"
    # This external script logic remains unchanged
    if [ -z $(curl -s4m5 icanhazip.com -k) ]; then
    curl -sSL https://gitlab.com/rwkgyg/CFwarp/raw/main/point/endip.sh -o endip.sh && chmod +x endip.sh && (echo -e "1\n2\n") | bash endip.sh > /dev/null 2>&1
    nwgip=$(awk -F, 'NR==2 {print $1}' /root/result.csv 2>/dev/null | grep -o '\[.*\]' | tr -d '[]')
    nwgpo=$(awk -F, 'NR==2 {print $1}' /root/result.csv 2>/dev/null | awk -F "]" '{print $2}' | tr -d ':')
    else
    curl -sSL https://gitlab.com/rwkgyg/CFwarp/raw/main/point/endip.sh -o endip.sh && chmod +x endip.sh && (echo -e "1\n1\n") | bash endip.sh > /dev/null 2>&1
    nwgip=$(awk -F, 'NR==2 {print $1}' /root/result.csv 2>/dev/null | awk -F: '{print $1}')
    nwgpo=$(awk -F, 'NR==2 {print $1}' /root/result.csv 2>/dev/null | awk -F: '{print $2}')
    fi
    a=$(cat /root/result.csv 2>/dev/null | awk -F, '$3!="timeout ms" {print} ' | sed -n '2p' | awk -F ',' '{print $2}')
    if [[ -z $a || $a = "100.00%" ]]; then
    if [[ -z $(curl -s4m5 icanhazip.com -k) ]]; then
    nwgip=2606:4700:d0::a29f:c001
    nwgpo=2408
    else
    nwgip=162.159.192.1
    nwgpo=2408
    fi
    fi
    
    # --- JQ Write Operations for Option 2 ---
    if [[ -z "$nwgip" || -z "$nwgpo" ]]; then
        red "獲取優選IP失敗，操作中止。"
        rm -rf /root/result.csv /root/endip.sh 
        changeserv
        return
    fi

    # sb10 (v1.10)
    local query10
    query10='(.outbounds[] | select(.type == "wireguard") | .server) = "'"$nwgip"'"'
    query10+=' | (.outbounds[] | select(.type == "wireguard") | .server_port) = '"$nwgpo"''
    
    # sb11 (v1.11+)
    local query11
    query11='(.endpoints[] | select(.tag == "warp-out") | .peers[0].address) = "'"$nwgip"'"'
    query11+=' | (.endpoints[] | select(.tag == "warp-out") | .peers[0].port) = '"$nwgpo"''

    # Apply to sb10.json
    jq "$query10" /etc/s-box/sb10.json > /etc/s-box/sb10.json.tmp
    if [[ $? -ne 0 || ! -s /etc/s-box/sb10.json.tmp ]]; then
        red "jq 處理 sb10.json 失敗！" && rm -f /etc/s-box/sb10.json.tmp
    else
        mv /etc/s-box/sb10.json.tmp /etc/s-box/sb10.json
    fi
    
    # Apply to sb11.json
    jq "$query11" /etc/s-box/sb11.json > /etc/s-box/sb11.json.tmp
    if [[ $? -ne 0 || ! -s /etc/s-box/sb11.json.tmp ]]; then
        red "jq 處理 sb11.json 失敗！" && rm -f /etc/s-box/sb11.json.tmp
    else
        mv /etc/s-box/sb11.json.tmp /etc/s-box/sb11.json
    fi
    # --- End JQ Write ---

    rm -rf /etc/s-box/sb.json
    cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
    restartsb
    rm -rf /root/result.csv /root/endip.sh 
    echo
    green "優選完畢，當前使用的對端IP：$nwgip:$nwgpo"
else
    changeserv
fi
}

sbymfl(){
sbport=$(cat /etc/s-box/sbwpph.log 2>/dev/null | awk '{print $3}' | awk -F":" '{print $NF}') 
sbport=${sbport:-'40000'}
resv1=$(curl -s --socks5 localhost:$sbport icanhazip.com)
resv2=$(curl -sx socks5h://localhost:$sbport icanhazip.com)
if [[ -z $resv1 && -z $resv2 ]]; then
warp_s4_ip='Socks5-IPV4未啓動，黑名單模式'
warp_s6_ip='Socks5-IPV6未啓動，黑名單模式'
else
warp_s4_ip='Socks5-IPV4可用'
warp_s6_ip='Socks5-IPV6自測'
fi
v4v6
if [[ -z $v4 ]]; then
vps_ipv4='無本地IPV4，黑名單模式'      
vps_ipv6="當前IP：$v6"
elif [[ -n $v4 &&  -n $v6 ]]; then
vps_ipv4="當前IP：$v4"    
vps_ipv6="當前IP：$v6"
else
vps_ipv4="當前IP：$v4"    
vps_ipv6='無本地IPV6，黑名單模式'
fi
unset swg4 swd4 swd6 swg6 ssd4 ssg4 ssd6 ssg6 sad4 sag4 sad6 sag6
wd4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[1].domain_suffix | join(" ")')
wg4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[1].geosite | join(" ")' 2>/dev/null)
if [[ "$wd4" == "yg_kkk" && ("$wg4" == "yg_kkk" || -z "$wg4") ]]; then
wfl4="${yellow}【warp出站IPV4可用】未分流${plain}"
else
if [[ "$wd4" != "yg_kkk" ]]; then
swd4="$wd4 "
fi
if [[ "$wg4" != "yg_kkk" ]]; then
swg4=$wg4
fi
wfl4="${yellow}【warp出站IPV4可用】已分流：$swd4$swg4${plain} "
fi

wd6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[2].domain_suffix | join(" ")')
wg6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[2].geosite | join(" ")' 2>/dev/null)
if [[ "$wd6" == "yg_kkk" && ("$wg6" == "yg_kkk"|| -z "$wg6") ]]; then
wfl6="${yellow}【warp出站IPV6自測】未分流${plain}"
else
if [[ "$wd6" != "yg_kkk" ]]; then
swd6="$wd6 "
fi
if [[ "$wg6" != "yg_kkk" ]]; then
swg6=$wg6
fi
wfl6="${yellow}【warp出站IPV6自測】已分流：$swd6$swg6${plain} "
fi

sd4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[3].domain_suffix | join(" ")')
sg4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[3].geosite | join(" ")' 2>/dev/null)
if [[ "$sd4" == "yg_kkk" && ("$sg4" == "yg_kkk" || -z "$sg4") ]]; then
sfl4="${yellow}【$warp_s4_ip】未分流${plain}"
else
if [[ "$sd4" != "yg_kkk" ]]; then
ssd4="$sd4 "
fi
if [[ "$sg4" != "yg_kkk" ]]; then
ssg4=$sg4
fi
sfl4="${yellow}【$warp_s4_ip】已分流：$ssd4$ssg4${plain} "
fi

sd6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[4].domain_suffix | join(" ")')
sg6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[4].geosite | join(" ")' 2>/dev/null)
if [[ "$sd6" == "yg_kkk" && ("$sg6" == "yg_kkk" || -z "$sg6") ]]; then
sfl6="${yellow}【$warp_s6_ip】未分流${plain}"
else
if [[ "$sd6" != "yg_kkk" ]]; then
ssd6="$sd6 "
fi
if [[ "$sg6" != "yg_kkk" ]]; then
ssg6=$sg6
fi
sfl6="${yellow}【$warp_s6_ip】已分流：$ssd6$ssg6${plain} "
fi

ad4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[5].domain_suffix | join(" ")')
ag4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[5].geosite | join(" ")' 2>/dev/null)
if [[ "$ad4" == "yg_kkk" && ("$ag4" == "yg_kkk" || -z "$ag4") ]]; then
adfl4="${yellow}【$vps_ipv4】未分流${plain}" 
else
if [[ "$ad4" != "yg_kkk" ]]; then
sad4="$ad4 "
fi
if [[ "$ag4" != "yg_kkk" ]]; then
sag4=$ag4
fi
adfl4="${yellow}【$vps_ipv4】已分流：$sad4$sag4${plain} "
fi

ad6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[6].domain_suffix | join(" ")')
ag6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[6].geosite | join(" ")' 2>/dev/null)
if [[ "$ad6" == "yg_kkk" && ("$ag6" == "yg_kkk" || -z "$ag6") ]]; then
adfl6="${yellow}【$vps_ipv6】未分流${plain}" 
else
if [[ "$ad6" != "yg_kkk" ]]; then
sad6="$ad6 "
fi
if [[ "$ag6" != "yg_kkk" ]]; then
sag6=$ag6
fi
adfl6="${yellow}【$vps_ipv6】已分流：$sad6$sag6${plain} "
fi
}

changefl(){
sbactive
blue "對所有協議進行統一的域名分流"
blue "為確保分流可用，雙棧IP（IPV4/IPV6）分流模式為優先模式"
blue "warp-wireguard默認開啓 (選項1與2)"
blue "socks5需要在VPS安裝warp官方客戶端或者WARP-plus-Socks5-賽風VPN (選項3與4)"
blue "VPS本地出站分流(選項5與6)"
echo
[[ "$sbnh" == "1.10" ]] && blue "當前Sing-box內核支持geosite分流方式" || blue "當前Sing-box內核不支持geosite分流方式，僅支持分流2、3、5、6選項"
echo
yellow "注意："
yellow "一、完整域名方式只能填完整域名 (例：谷歌網站填寫：www.google.com)"
yellow "二、geosite方式須填寫geosite規則名 (例：奈飛填寫:netflix ；迪士尼填寫:disney ；ChatGPT填寫:openai ；全局且繞過中國填寫:geolocation-!cn)"
yellow "三、同一個完整域名或者geosite切勿重復分流"
yellow "四、如分流通道中有個別通道無網絡，所填分流為黑名單模式，即屏蔽該網站訪問"
changef
}

changef(){
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
sbymfl
echo
if [[ "$sbnh" != "1.10" ]]; then
wfl4='(當前內核不支持)'
sfl6='(當前內核不支持)'
fi
green "1：重置warp-wireguard-ipv4優先分流域名 $wfl4"
green "2：重置warp-wireguard-ipv6優先分流域名 $wfl6"
green "3：重置warp-socks5-ipv4優先分流域名 $sfl4"
green "4：重置warp-socks5-ipv6優先分流域名 $sfl6"
green "5：重置VPS本地ipv4優先分流域名 $adfl4"
green "6：重置VPS本地ipv6優先分流域名 $adfl6"
green "0：返回上層"
echo
readp "請選擇【0-6】：" menu

# --- JQ 核心修復 ---

# 輔助函數：將 "a b c" 轉換為 jq 陣列 '["a", "b", "c"]'
_jq_array_str() {
    local input_str="$1"
    if [ -z "$input_str" ]; then
        echo '["yg_kkk"]'
    else
        # 將空格替換為 '", "'
        local formatted_str
        formatted_str=$(echo "$input_str" | sed 's/ /", "/g')
        echo '["'"$formatted_str"'"]'
    fi
}

# 輔助函數：安全地更新所有 JSON 檔案
# 用法: _safe_jq_update "jq_query_for_sb10" "jq_query_for_sb11"
_safe_jq_update() {
    local query_sb10="$1"
    local query_sb11="$2"
    local success=true
    
    # $sbfiles 變數包含 sb10.json, sb11.json, 和 sb.json
    for file in $sbfiles; do
        if [[ ! -f "$file" ]]; then continue; fi
        
        local query_to_run=""
        
        if [[ "$file" == "/etc/s-box/sb10.json" ]]; then
            query_to_run="$query_sb10"
        elif [[ "$file" == "/etc/s-box/sb11.json" ]]; then
            query_to_run="$query_sb11"
        elif [[ "$file" == "/etc/s-box/sb.json" ]]; then
            # 根據當前內核版本選擇 query
            [[ "$sbnh" == "1.10" ]] && query_to_run="$query_sb10" || query_to_run="$query_sb11"
        fi

        # 如果 query 為 "skip"，則跳過此檔案
        if [[ "$query_to_run" == "skip" || -z "$query_to_run" ]]; then
            continue
        fi

        # 執行 jq
        jq "$query_to_run" "$file" > "$file.tmp"
        
        if [[ $? -ne 0 || ! -s "$file.tmp" ]]; then
            red "jq 處理 $file 失敗！"
            rm -f "$file.tmp"
            success=false
        else
            mv "$file.tmp" "$file"
        fi
    done
    
    if [[ "$success" = false ]]; then
        red "配置更新失敗，請檢查 jq 是否已安裝。"
        readp "按任意鍵返回..." key
        sb
        return 1
    fi
    return 0
}
# --- JQ 修復結束 ---

local rule_type=""
local query_sb10=""
local query_sb11=""
local input_values=""
local rule_menu=""

if [ "$menu" = "1" ]; then # warp-ipv4 (sb10 only)
    if [[ "$sbnh" != "1.10" ]]; then
        yellow "遺憾！當前Sing-box內核不支持此分流。" && sleep 2 && changef
        return
    fi
    readp "1：使用完整域名方式\n2：使用geosite方式\n3：返回上層\n請選擇：" rule_menu
    if [ "$rule_menu" = "1" ]; then
        readp "輸入完整域名 (空格分隔):" input_values
        rule_type="domain_suffix"
        query_sb10='(.route.rules[] | select(.outbound == "warp-IPv4-out") | .'"$rule_type"') = '$(_jq_array_str "$input_values")
        query_sb11="skip" # sb11 不支持
    elif [ "$rule_menu" = "2" ]; then
        readp "輸入geosite規則 (空格分隔):" input_values
        rule_type="geosite"
        query_sb10='(.route.rules[] | select(.outbound == "warp-IPv4-out") | .'"$rule_type"') = '$(_jq_array_str "$input_values")
        query_sb11="skip" # sb11 不支持
    else
        changef && return
    fi

elif [ "$menu" = "2" ]; then # warp-ipv6 (sb10) / warp-out (sb11)
    readp "1：使用完整域名方式\n2：使用geosite方式\n3：返回上層\n請選擇：" rule_menu
    if [ "$rule_menu" = "1" ]; then
        readp "輸入完整域名 (空格分隔):" input_values
        rule_type="domain_suffix"
        query_sb10='(.route.rules[] | select(.outbound == "warp-IPv6-out") | .'"$rule_type"') = '$(_jq_array_str "$input_values")
        query_sb11='(.route.rules[] | select(.outbound == "warp-out") | .'"$rule_type"') = '$(_jq_array_str "$input_values")
    elif [ "$rule_menu" = "2" ]; then
        if [[ "$sbnh" != "1.10" ]]; then
            yellow "遺憾！當前Sing-box內核不支持geosite分流方式。" && sleep 2 && changef
            return
        fi
        readp "輸入geosite規則 (空格分隔):" input_values
        rule_type="geosite"
        query_sb10='(.route.rules[] | select(.outbound == "warp-IPv6-out") | .'"$rule_type"') = '$(_jq_array_str "$input_values")
        query_sb11="skip" # sb11 不支持 geosite
    else
        changef && return
    fi

elif [ "$menu" = "3" ]; then # socks-ipv4 (sb10) / socks-out (sb11)
    readp "1：使用完整域名方式\n2：使用geosite方式\n3：返回上層\n請選擇：" rule_menu
    if [ "$rule_menu" = "1" ]; then
        readp "輸入完整域名 (空格分隔):" input_values
        rule_type="domain_suffix"
        query_sb10='(.route.rules[] | select(.outbound == "socks-IPv4-out") | .'"$rule_type"') = '$(_jq_array_str "$input_values")
        query_sb11='(.route.rules[] | select(.outbound == "socks-out") | .'"$rule_type"') = '$(_jq_array_str "$input_values")
    elif [ "$rule_menu" = "2" ]; then
        if [[ "$sbnh" != "1.10" ]]; then
            yellow "遺憾！當前Sing-box內核不支持geosite分流方式。" && sleep 2 && changef
            return
        fi
        readp "輸入geosite規則 (空格分隔):" input_values
        rule_type="geosite"
        query_sb10='(.route.rules[] | select(.outbound == "socks-IPv4-out") | .'"$rule_type"') = '$(_jq_array_str "$input_values")
        query_sb11="skip" # sb11 不支持 geosite
    else
        changef && return
    fi

elif [ "$menu" = "4" ]; then # socks-ipv6 (sb10 only)
    if [[ "$sbnh" != "1.10" ]]; then
        yellow "遺憾！當前Sing-box內核不支持此分流。" && sleep 2 && changef
        return
    fi
    readp "1：使用完整域名方式\n2：使用geosite方式\n3：返回上層\n請選擇：" rule_menu
    if [ "$rule_menu" = "1" ]; then
        readp "輸入完整域名 (空格分隔):" input_values
        rule_type="domain_suffix"
        query_sb10='(.route.rules[] | select(.outbound == "socks-IPv6-out") | .'"$rule_type"') = '$(_jq_array_str "$input_values")
        query_sb11="skip"
    elif [ "$rule_menu" = "2" ]; then
        readp "輸入geosite規則 (空格分隔):" input_values
        rule_type="geosite"
        query_sb10='(.route.rules[] | select(.outbound == "socks-IPv6-out") | .'"$rule_type"') = '$(_jq_array_str "$input_values")
        query_sb11="skip"
    else
        changef && return
    fi

elif [ "$menu" = "5" ]; then # vps-v4 (both)
    readp "1：使用完整域名方式\n2：使用geosite方式\n3：返回上層\n請選擇：" rule_menu
    if [ "$rule_menu" = "1" ]; then
        readp "輸入完整域名 (空格分隔):" input_values
        rule_type="domain_suffix"
        query_sb10='(.route.rules[] | select(.outbound == "vps-outbound-v4") | .'"$rule_type"') = '$(_jq_array_str "$input_values")
        query_sb11='(.route.rules[] | select(.outbound == "vps-outbound-v4") | .'"$rule_type"') = '$(_jq_array_str "$input_values")
    elif [ "$rule_menu" = "2" ]; then
        if [[ "$sbnh" != "1.10" ]]; then
            yellow "遺憾！當前Sing-box內核不支持geosite分流方式。" && sleep 2 && changef
            return
        fi
        readp "輸入geosite規則 (空格分隔):" input_values
        rule_type="geosite"
        query_sb10='(.route.rules[] | select(.outbound == "vps-outbound-v4") | .'"$rule_type"') = '$(_jq_array_str "$input_values")
        query_sb11="skip" # sb11 不支持 geosite
    else
        changef && return
    fi

elif [ "$menu" = "6" ]; then # vps-v6 (both)
    readp "1：使用完整域名方式\n2：使用geosite方式\n3：返回上層\n請選擇：" rule_menu
    if [ "$rule_menu" = "1" ]; then
        readp "輸入完整域名 (空格分隔):" input_values
        rule_type="domain_suffix"
        query_sb10='(.route.rules[] | select(.outbound == "vps-outbound-v6") | .'"$rule_type"') = '$(_jq_array_str "$input_values")
        query_sb11='(.route.rules[] | select(.outbound == "vps-outbound-v6") | .'"$rule_type"') = '$(_jq_array_str "$input_values")
    elif [ "$rule_menu" = "2" ]; then
        if [[ "$sbnh" != "1.10" ]]; then
            yellow "遺憾！當前Sing-box內核不支持geosite分流方式。" && sleep 2 && changef
            return
        fi
        readp "輸入geosite規則 (空格分隔):" input_values
        rule_type="geosite"
        query_sb10='(.route.rules[] | select(.outbound == "vps-outbound-v6") | .'"$rule_type"') = '$(_jq_array_str "$input_values")
        query_sb11="skip" # sb11 不支持 geosite
    else
        changef && return
    fi
else
    sb && return
fi

# 執行 JQ 更新
_safe_jq_update "$query_sb10" "$query_sb11"
restartsb
changef # 返回分流菜單
}

restartsb(){
if [[ x"${release}" == x"alpine" ]]; then
rc-service sing-box restart
else
systemctl enable sing-box
systemctl start sing-box
systemctl restart sing-box
fi
}

stclre(){
if [[ ! -f '/etc/s-box/sb.json' ]]; then
red "未正常安裝Sing-box" && exit
fi
readp "1：重啓\n2：關閉\n請選擇：" menu
if [ "$menu" = "1" ]; then
restartsb
sbactive
green "Sing-box服務已重啓\n" && sleep 3 && sb
elif [ "$menu" = "2" ]; then
if [[ x"${release}" == x"alpine" ]]; then
rc-service sing-box stop
else
systemctl stop sing-box
systemctl disable sing-box
fi
green "Sing-box服務已關閉\n" && sleep 3 && sb
else
stclre
fi
}

cronsb(){
uncronsb
crontab -l > /tmp/crontab.tmp
echo "0 1 * * * systemctl restart sing-box;rc-service sing-box restart" >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
}
uncronsb(){
crontab -l > /tmp/crontab.tmp
sed -i '/sing-box/d' /tmp/crontab.tmp
sed -i '/sbargopid/d' /tmp/crontab.tmp
sed -i '/sbargoympid/d' /tmp/crontab.tmp
sed -i '/sbwpphid.log/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
}

lnsb(){
rm -rf /usr/bin/sb
curl -L -o /usr/bin/sb -# --retry 2 --insecure https://raw.githubusercontent.com/yat-muk/sing-box-yg/main/sb.sh
chmod +x /usr/bin/sb
}

upsbyg(){
if [[ ! -f '/usr/bin/sb' ]]; then
red "未正常安裝Sing-box-yg" && exit
fi
lnsb
curl -sL https://raw.githubusercontent.com/yat-muk/sing-box-yg/main/version | awk -F "更新內容" '{print $1}' | head -n 1 > /etc/s-box/v
green "Sing-box-yg安裝腳本升級成功" && sleep 5 && sb
}

lapre(){
latcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]+",' | sed -n 1p | tr -d '",')
precore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]*-[^"]*"' | sed -n 1p | tr -d '",')
inscore=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}')
}

upsbcroe(){
sbactive
lapre
[[ $inscore =~ ^[0-9.]+$ ]] && lat="【已安裝v$inscore】" || pre="【已安裝v$inscore】"
green "1：升級/切換Sing-box最新正式版 v$latcore  ${bblue}${lat}${plain}"
green "2：升級/切換Sing-box最新測試版 v$precore  ${bblue}${pre}${plain}"
green "3：切換Sing-box某個正式版或測試版，需指定版本號 (建議1.10.0以上版本)"
green "0：返回上層"
readp "請選擇【0-3】：" menu
if [ "$menu" = "1" ]; then
upcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]+",' | sed -n 1p | tr -d '",')
elif [ "$menu" = "2" ]; then
upcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]*-[^"]*"' | sed -n 1p | tr -d '",')
elif [ "$menu" = "3" ]; then
echo
red "注意: 版本號在 https://github.com/SagerNet/sing-box/tags 可查，且有Downloads字樣 (必須1.10.0以上版本)"
green "正式版版本號格式：數字.數字.數字 (例：1.10.7   注意，1.10系列內核支持geosite分流，1.10以上內核不支持geosite分流"
green "測試版版本號格式：數字.數字.數字-alpha或rc或beta.數字 (例：1.10.0-alpha或rc或beta.1)"
readp "請輸入Sing-box版本號：" upcore
else
sb
fi
if [[ -n $upcore ]]; then
green "開始下載並更新Sing-box內核……請稍等"
sbname="sing-box-$upcore-linux-$cpu"
curl -L -o /etc/s-box/sing-box.tar.gz  -# --retry 2 https://github.com/SagerNet/sing-box/releases/download/v$upcore/$sbname.tar.gz
if [[ -f '/etc/s-box/sing-box.tar.gz' ]]; then
tar xzf /etc/s-box/sing-box.tar.gz -C /etc/s-box
mv /etc/s-box/$sbname/sing-box /etc/s-box
rm -rf /etc/s-box/{sing-box.tar.gz,$sbname}
if [[ -f '/etc/s-box/sing-box' ]]; then
chown root:root /etc/s-box/sing-box
chmod +x /etc/s-box/sing-box
sbnh=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}' | cut -d '.' -f 1,2)
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
rm -rf /etc/s-box/sb.json
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
blue "成功升級/切換 Sing-box 內核版本：$(/etc/s-box/sing-box version | awk '/version/{print $NF}')" && sleep 3 && sb
else
red "下載 Sing-box 內核不完整，安裝失敗，請重試" && upsbcroe
fi
else
red "下載 Sing-box 內核失敗或不存在，請重試" && upsbcroe
fi
else
red "版本號檢測出錯，請重試" && upsbcroe
fi
}

unins(){
if [[ x"${release}" == x"alpine" ]]; then
rc-service sing-box stop
rc-update del sing-box default
rm /etc/init.d/sing-box -f
else
systemctl stop sing-box >/dev/null 2>&1
systemctl disable sing-box >/dev/null 2>&1
rm -f /etc/systemd/system/sing-box.service
fi
kill -15 $(cat /etc/s-box/sbargopid.log 2>/dev/null) >/dev/null 2>&1
kill -15 $(cat /etc/s-box/sbargoympid.log 2>/dev/null) >/dev/null 2>&1
kill -15 $(cat /etc/s-box/sbwpphid.log 2>/dev/null) >/dev/null 2>&1
rm -rf /etc/s-box sbyg_update /usr/bin/sb /root/geoip.db /root/geosite.db /root/warpapi /root/warpip
uncronsb
iptables -t nat -F PREROUTING >/dev/null 2>&1
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
green "Sing-box卸載完成！"
blue "歡迎繼續使用Sing-box-yg腳本：bash <(curl -Ls https://raw.githubusercontent.com/yat-muk/sing-box-yg/main/sb.sh)"
echo
}

sblog(){
red "退出日誌 Ctrl+c"
if [[ x"${release}" == x"alpine" ]]; then
yellow "暫不支持alpine查看日誌"
else
#systemctl status sing-box
journalctl -u sing-box.service -o cat -f
fi
}

sbactive(){
if [[ ! -f /etc/s-box/sb.json ]]; then
red "未正常啓動Sing-box，請卸載重裝或者選擇10查看運行日誌反饋" && exit
fi
}

sbshare(){
rm -rf /etc/s-box/jhdy.txt /etc/s-box/vl_reality.txt /etc/s-box/vm_ws_argols.txt /etc/s-box/vm_ws_argogd.txt /etc/s-box/vm_ws.txt /etc/s-box/vm_ws_tls.txt /etc/s-box/hy2.txt /etc/s-box/tuic5.txt /etc/s-box/anytls.txt
result_vl_vm_hy_tu && resvless && resvmess && reshy2 && restu5 && resanytls
cat /etc/s-box/vl_reality.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/vm_ws_argols.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/vm_ws_argogd.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/vm_ws.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/vm_ws_tls.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/hy2.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/tuic5.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/anytls.txt 2>/dev/null >> /etc/s-box/jhdy.txt
baseurl=$(base64 -w 0 < /etc/s-box/jhdy.txt 2>/dev/null)
v2sub=$(cat /etc/s-box/jhdy.txt 2>/dev/null)
echo "$v2sub" > /etc/s-box/jh_sub.txt
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 五合一聚合訂閱 】節點信息如下：" && sleep 2
echo
echo "分享鏈接"
echo -e "${yellow}$baseurl${plain}"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
sb_client
}

clash_sb_share(){
sbactive
echo
yellow "1：刷新並查看各協議分享鏈接、二維碼、五合一聚合訂閱"
yellow "2：刷新並查看Clash-Meta、Sing-box客戶端SFA/SFI/SFW三合一配置、Gitlab私有訂閱鏈接"
yellow "3：刷新並查看Hysteria2、Tuic5的V2rayN客戶端自定義配置"
yellow "4：推送最新節點配置信息(選項1+選項2)到Telegram通知"
yellow "0：返回上層"
readp "請選擇【0-4】：" menu
if [ "$menu" = "1" ]; then
sbshare
elif  [ "$menu" = "2" ]; then
green "請稍等……"
sbshare > /dev/null 2>&1
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "Gitlab訂閱鏈接如下："
gitlabsubgo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vless-reality、vmess-ws、Hysteria2、Tuic5、AnyTLS 】Clash-Meta配置文件顯示如下："
red "文件目錄 /etc/s-box/clash_meta_client.yaml ，複製自建以yaml文件格式為準" && sleep 2
echo
cat /etc/s-box/clash_meta_client.yaml
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vless-reality、vmess-ws、Hysteria2、Tuic5、AnyTLS 】SFA/SFI/SFW配置文件顯示如下："
red "文件目錄 /etc/s-box/sing_box_client.json ，複製自建以json文件格式為準" && sleep 2
echo
cat /etc/s-box/sing_box_client.json
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
elif  [ "$menu" = "3" ]; then
green "請稍等……"
sbshare > /dev/null 2>&1
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 Hysteria-2 】自定義V2rayN配置文件顯示如下："
red "文件目錄 /etc/s-box/v2rayn_hy2.yaml ，複製自建以yaml文件格式為準" && sleep 2
echo
cat /etc/s-box/v2rayn_hy2.yaml
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
tu5_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.key_path')
if [[ "$tu5_sniname" = '/etc/s-box/private.key' ]]; then
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
red "注意：V2rayN客戶端使用自定義Tuic5官方客戶端核心時，不支持Tuic5自簽證書，僅支持域名證書" && sleep 2
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
else
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 Tuic-v5 】自定義V2rayN配置文件顯示如下："
red "文件目錄 /etc/s-box/v2rayn_tu5.json ，複製自建以json文件格式為準" && sleep 2
echo
cat /etc/s-box/v2rayn_tu5.json
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
fi
elif [ "$menu" = "4" ]; then
tgnotice
else
sb
fi
}

acme(){
#bash <(curl -Ls https://gitlab.com/rwkgyg/acme-script/raw/main/acme.sh)
bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)
}
cfwarp(){
#bash <(curl -Ls https://gitlab.com/rwkgyg/CFwarp/raw/main/CFwarp.sh)
bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/warp-yg/main/CFwarp.sh)
}
bbr(){
if [[ $vi =~ lxc|openvz ]]; then
yellow "當前VPS的架構為 $vi，不支持開啓原版BBR加速" && sleep 2 && exit 
else
green "點擊任意鍵，即可開啓BBR加速，ctrl+c退出"
bash <(curl -Ls https://raw.githubusercontent.com/teddysun/across/master/bbr.sh)
fi
}

showprotocol(){
allports
sbymfl
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
if [[ "$tls" = "false" ]]; then
argopid
if [[ -n $(ps -e | grep -w $ym 2>/dev/null) || -n $(ps -e | grep -w $ls 2>/dev/null) ]]; then
vm_zs="TLS關閉"
argoym="已開啓"
else
vm_zs="TLS關閉"
argoym="未開啓"
fi
else
vm_zs="TLS開啓"
argoym="不支持開啓"
fi
hy2_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].tls.key_path')
[[ "$hy2_sniname" = '/etc/s-box/private.key' ]] && hy2_zs="自簽證書" || hy2_zs="域名證書"
tu5_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.key_path')
[[ "$tu5_sniname" = '/etc/s-box/private.key' ]] && tu5_zs="自簽證書" || tu5_zs="域名證書"
anytls_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[4].listen_port')

echo -e "Sing-box節點關鍵信息、已分流域名情況如下："
echo -e "🚀【  Vless-reality 】${yellow}端口:$vl_port  Reality域名證書偽裝地址：$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.server_name')${plain}"
if [[ "$tls" = "false" ]]; then
echo -e "🚀【    Vmess-ws    】${yellow}端口:$vm_port   證書形式:$vm_zs   Argo狀態:$argoym${plain}"
else
echo -e "🚀【  Vmess-ws-tls  】${yellow}端口:$vm_port   證書形式:$vm_zs   Argo狀態:$argoym${plain}"
fi
echo -e "🚀【   Hysteria-2   】${yellow}端口:$hy2_port  證書形式:$hy2_zs  轉發多端口: $hy2zfport${plain}"
echo -e "🚀【    Tuic-v5     】${yellow}端口:$tu5_port  證書形式:$tu5_zs  轉發多端口: $tu5zfport${plain}"
echo -e "🚀【 AnyTLS-reality 】${yellow}端口:$anytls_port  Reality狀態:共用Vless設置${plain}"
if [ "$argoym" = "已開啓" ]; then
echo -e "Vmess-UUID：${yellow}$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].users[0].uuid')${plain}"
echo -e "Vmess-Path：${yellow}$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].transport.path')${plain}"
if [[ -n $(ps -e | grep -w $ls 2>/dev/null) ]]; then
echo -e "Argo臨時域名：${yellow}$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')${plain}"
fi
if [[ -n $(ps -e | grep -w $ym 2>/dev/null) ]]; then
echo -e "Argo固定域名：${yellow}$(cat /etc/s-box/sbargoym.log 2>/dev/null)${plain}"
fi
fi
echo "-----------------------------------------------------------------------------------------"
if [[ -n $(ps -e | grep sbwpph) ]]; then
s5port=$(cat /etc/s-box/sbwpph.log 2>/dev/null | awk '{print $3}'| awk -F":" '{print $NF}')
s5gj=$(cat /etc/s-box/sbwpph.log 2>/dev/null | awk '{print $6}')
case "$s5gj" in
AT) showgj="奧地利" ;;
AU) showgj="澳大利亞" ;;
BE) showgj="比利時" ;;
BG) showgj="保加利亞" ;;
CA) showgj="加拿大" ;;
CH) showgj="瑞士" ;;
CZ) showgj="捷克" ;;
DE) showgj="德國" ;;
DK) showgj="丹麥" ;;
EE) showgj="愛沙尼亞" ;;
ES) showgj="西班牙" ;;
FI) showgj="芬蘭" ;;
FR) showgj="法國" ;;
GB) showgj="英國" ;;
HR) showgj="克羅地亞" ;;
HU) showgj="匈牙利" ;;
IE) showgj="愛爾蘭" ;;
IN) showgj="印度" ;;
IT) showgj="意大利" ;;
JP) showgj="日本" ;;
LT) showgj="立陶宛" ;;
LV) showgj="拉脫維亞" ;;
NL) showgj="荷蘭" ;;
NO) showgj="挪威" ;;
PL) showgj="波蘭" ;;
PT) showgj="葡萄牙" ;;
RO) showgj="羅馬尼亞" ;;
RS) showgj="塞爾維亞" ;;
SE) showgj="瑞典" ;;
SG) showgj="新加坡" ;;
SK) showgj="斯洛伐克" ;;
US) showgj="美國" ;;
esac
grep -q "country" /etc/s-box/sbwpph.log 2>/dev/null && s5ms="多地區Psiphon代理模式 (端口:$s5port  國家:$showgj)" || s5ms="本地Warp代理模式 (端口:$s5port)"
echo -e "WARP-plus-Socks5狀態：$yellow已啓動 $s5ms$plain"
else
echo -e "WARP-plus-Socks5狀態：$yellow未啓動$plain"
fi
echo "-----------------------------------------------------------------------------------------"
ww4="warp-wireguard-ipv4優先分流域名：$wfl4"
ww6="warp-wireguard-ipv6優先分流域名：$wfl6"
ws4="warp-socks5-ipv4優先分流域名：$sfl4"
ws6="warp-socks5-ipv6優先分流域名：$sfl6"
l4="VPS本地ipv4優先分流域名：$adfl4"
l6="VPS本地ipv6優先分流域名：$adfl6"
[[ "$sbnh" == "1.10" ]] && ymflzu=("ww4" "ww6" "ws4" "ws6" "l4" "l6") || ymflzu=("ww6" "ws4" "l4" "l6")
for ymfl in "${ymflzu[@]}"; do
if [[ ${!ymfl} != *"未"* ]]; then
echo -e "${!ymfl}"
fi
done
if [[ $ww4 = *"未"* && $ww6 = *"未"* && $ws4 = *"未"* && $ws6 = *"未"* && $l4 = *"未"* && $l6 = *"未"* ]] ; then
echo -e "未設置域名分流"
fi
}

inssbwpph(){
sbactive
ins(){
if [ ! -e /etc/s-box/sbwpph ]; then
case $(uname -m) in
aarch64) cpu=arm64;;
x86_64) cpu=amd64;;
esac
curl -L -o /etc/s-box/sbwpph -# --retry 2 --insecure https://raw.githubusercontent.com/yat-muk/sing-box-yg/main/sbwpph_$cpu
chmod +x /etc/s-box/sbwpph
fi
if [[ -n $(ps -e | grep sbwpph) ]]; then
kill -15 $(cat /etc/s-box/sbwpphid.log 2>/dev/null) >/dev/null 2>&1
fi
v4v6
if [[ -n $v4 ]]; then
sw46=4
else
red "IPV4不存在，確保安裝過WARP-IPV4模式"
sw46=6
fi
echo
readp "設置WARP-plus-Socks5端口（回車跳過端口默認40000）：" port
if [[ -z $port ]]; then
port=40000
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] 
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义端口:" port
done
else
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义端口:" port
done
fi
s5port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[] | select(.type == "socks") | .server_port')
[[ "$sbnh" == "1.10" ]] && num=10 || num=11

# --- JQ 核心修復 ---
# 構建精確的 jq 查詢
local query='(.outbounds[] | select(.tag == "socks-out") | .server_port) = '"$port"
local success=true

# 1. 修正 sb10.json
jq "$query" /etc/s-box/sb10.json > /etc/s-box/sb10.json.tmp
if [[ $? -ne 0 || ! -s /etc/s-box/sb10.json.tmp ]]; then
    red "jq 處理 sb10.json 失敗！" && rm -f /etc/s-box/sb10.json.tmp
    success=false
else
    mv /etc/s-box/sb10.json.tmp /etc/s-box/sb10.json
fi

# 2. 修正 sb11.json
jq "$query" /etc/s-box/sb11.json > /etc/s-box/sb11.json.tmp
if [[ $? -ne 0 || ! -s /etc/s-box/sb11.json.tmp ]]; then
    red "jq 處理 sb11.json 失敗！" && rm -f /etc/s-box/sb11.json.tmp
    success=false
else
    mv /etc/s-box/sb11.json.tmp /etc/s-box/sb11.json
fi

if [[ "$success" = false ]]; then
     red "Socks5 端口更新失敗，請檢查 jq 是否已安裝。"
     readp "按任意鍵返回..." key
     sb
     return 1
fi
# --- JQ 修復結束 ---

rm -rf /etc/s-box/sb.json
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
}
unins(){
kill -15 $(cat /etc/s-box/sbwpphid.log 2>/dev/null) >/dev/null 2>&1
rm -rf /etc/s-box/sbwpph.log /etc/s-box/sbwpphid.log
crontab -l > /tmp/crontab.tmp
sed -i '/sbwpphid.log/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
}
echo
yellow "1：重置啓用WARP-plus-Socks5本地Warp代理模式"
yellow "2：重置啓用WARP-plus-Socks5多地區Psiphon代理模式"
yellow "3：停止WARP-plus-Socks5代理模式"
yellow "0：返回上層"
readp "請選擇【0-3】：" menu
if [ "$menu" = "1" ]; then
ins
nohup setsid /etc/s-box/sbwpph -b 127.0.0.1:$port --gool -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1 & echo "$!" > /etc/s-box/sbwpphid.log
green "申請IP中……請稍等……" && sleep 20
resv1=$(curl -s --socks5 localhost:$port icanhazip.com)
resv2=$(curl -sx socks5h://localhost:$port icanhazip.com)
if [[ -z $resv1 && -z $resv2 ]]; then
red "WARP-plus-Socks5的IP獲取失敗" && unins && exit
else
echo "/etc/s-box/sbwpph -b 127.0.0.1:$port --gool -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1" > /etc/s-box/sbwpph.log
crontab -l > /tmp/crontab.tmp
sed -i '/sbwpphid.log/d' /tmp/crontab.tmp
echo '@reboot sleep 10 && /bin/bash -c "nohup setsid $(cat /etc/s-box/sbwpph.log 2>/dev/null) & pid=\$! && echo \$pid > /etc/s-box/sbwpphid.log"' >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
green "WARP-plus-Socks5的IP獲取成功，可進行Socks5代理分流"
fi
elif [ "$menu" = "2" ]; then
ins
echo '
奧地利（AT）
澳大利亞（AU）
比利時（BE）
保加利亞（BG）
加拿大（CA）
瑞士（CH）
捷克 (CZ)
德國（DE）
丹麥（DK）
愛沙尼亞（EE）
西班牙（ES）
芬蘭（FI）
法國（FR）
英國（GB）
克羅地亞（HR）
匈牙利 (HU)
愛爾蘭（IE）
印度（IN）
意大利 (IT)
日本（JP）
立陶宛（LT）
拉脫維亞（LV）
荷蘭（NL）
挪威 (NO)
波蘭（PL）
葡萄牙（PT）
羅馬尼亞 (RO)
塞爾維亞（RS）
瑞典（SE）
新加坡 (SG)
斯洛伐克（SK）
美國（US）
'
readp "可選擇國家地區（輸入末尾兩個大寫字母，如美國，則輸入US）：" guojia
nohup setsid /etc/s-box/sbwpph -b 127.0.0.1:$port --cfon --country $guojia -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1 & echo "$!" > /etc/s-box/sbwpphid.log
green "申請IP中……請稍等……" && sleep 20
resv1=$(curl -s --socks5 localhost:$port icanhazip.com)
resv2=$(curl -sx socks5h://localhost:$port icanhazip.com)
if [[ -z $resv1 && -z $resv2 ]]; then
red "WARP-plus-Socks5的IP獲取失敗，嘗試換個國家地區吧" && unins && exit
else
echo "/etc/s-box/sbwpph -b 127.0.0.1:$port --cfon --country $guojia -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1" > /etc/s-box/sbwpph.log
crontab -l > /tmp/crontab.tmp
sed -i '/sbwpphid.log/d' /tmp/crontab.tmp
echo '@reboot sleep 10 && /bin/bash -c "nohup setsid $(cat /etc/s-box/sbwpph.log 2>/dev/null) & pid=\$! && echo \$pid > /etc/s-box/sbwpphid.log"' >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
green "WARP-plus-Socks5的IP獲取成功，可進行Socks5代理分流"
fi
elif [ "$menu" = "3" ]; then
unins && green "已停止WARP-plus-Socks5代理功能"
else
sb
fi
}

sbsm(){
echo
blue "sing-box-yg腳本項目地址：https://github.com/yat-muk/sing-box-yg"
echo
}

clear
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
echo "Github項目：github.com/yat-muk/sing-box-yg"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
echo "Vless-reality-vision、Vmess-ws(tls)+Argo、Hysteria-2、Tuic-v5、AnyTLS-reality 五協議共存腳本"
echo "腳本快捷方式：sb"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green " 1. 一鍵安裝 Sing-box" 
green " 2. 刪除卸載 Sing-box"
white "-----------------------------------------------------------------------------------------"
green " 3. 變更配置 【雙證書TLS/UUID路徑/Argo/IP優先/TG通知/Warp/訂閱/CDN優選】" 
green " 4. 更改主端口/添加多端口跳躍復用" 
green " 5. 三通道域名分流"
green " 6. 關閉/重啓 Sing-box"   
green " 7. 更新 Sing-box-yg 腳本"
green " 8. 更新/切換/指定 Sing-box 內核版本"
white "-----------------------------------------------------------------------------------------"
green " 9. 刷新並查看節點 【Clash-Meta/SFA+SFI+SFW三合一配置/訂閱鏈接/推送TG通知】"
green "10. 查看 Sing-box 運行日誌"
green "11. 一鍵原版BBR+FQ加速"
green "12. 管理 Acme 申請域名證書"
green "13. 管理 Warp 查看Netflix/ChatGPT解鎖情況"
green "14. 添加 WARP-plus-Socks5 代理模式 【本地Warp/多地區Psiphon-VPN】"
green "15. 雙棧VPS切換IPV4/IPV6配置輸出"
white "-----------------------------------------------------------------------------------------"
green "16. Sing-box-yg腳本使用說明書"
white "-----------------------------------------------------------------------------------------"
green " 0. 退出腳本"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
insV=$(cat /etc/s-box/v 2>/dev/null)
latestV=$(curl -sL https://raw.githubusercontent.com/yat-muk/sing-box-yg/main/version | awk -F "更新內容" '{print $1}' | head -n 1)
if [ -f /etc/s-box/v ]; then
if [ "$insV" = "$latestV" ]; then
echo -e "當前 Sing-box-yg 腳本最新版：${bblue}${insV}${plain} (已安裝)"
else
echo -e "當前 Sing-box-yg 腳本版本號：${bblue}${insV}${plain}"
echo -e "檢測到最新 Sing-box-yg 腳本版本號：${yellow}${latestV}${plain} (可選擇7進行更新)"
echo -e "${yellow}$(curl -sL https://raw.githubusercontent.com/yat-muk/sing-box-yg/main/version)${plain}"
fi
else
echo -e "當前 Sing-box-yg 腳本版本號：${bblue}${latestV}${plain}"
yellow "未安裝 Sing-box-yg 腳本！請先選擇 1 安裝"
fi

lapre
if [ -f '/etc/s-box/sb.json' ]; then
if [[ $inscore =~ ^[0-9.]+$ ]]; then
if [ "${inscore}" = "${latcore}" ]; then
echo
echo -e "當前 Sing-box 最新正式版內核：${bblue}${inscore}${plain} (已安裝)"
echo
echo -e "當前 Sing-box 最新測試版內核：${bblue}${precore}${plain} (可切換)"
else
echo
echo -e "當前 Sing-box 已安裝正式版內核：${bblue}${inscore}${plain}"
echo -e "檢測到最新 Sing-box 正式版內核：${yellow}${latcore}${plain} (可選擇8進行更新)"
echo
echo -e "當前 Sing-box 最新測試版內核：${bblue}${precore}${plain} (可切換)"
fi
else
if [ "${inscore}" = "${precore}" ]; then
echo
echo -e "當前 Sing-box 最新測試版內核：${bblue}${inscore}${plain} (已安裝)"
echo
echo -e "當前 Sing-box 最新正式版內核：${bblue}${latcore}${plain} (可切換)"
else
echo
echo -e "當前 Sing-box 已安裝測試版內核：${bblue}${inscore}${plain}"
echo -e "檢測到最新 Sing-box 測試版內核：${yellow}${precore}${plain} (可選擇8進行更新)"
echo
echo -e "當前 Sing-box 最新正式版內核：${bblue}${latcore}${plain} (可切換)"
fi
fi
else
echo
echo -e "當前 Sing-box 最新正式版內核：${bblue}${latcore}${plain}"
echo -e "當前 Sing-box 最新測試版內核：${bblue}${precore}${plain}"
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo -e "VPS狀態如下："
echo -e "系統:$blue$op$plain  \c";echo -e "內核:$blue$version$plain  \c";echo -e "處理器:$blue$cpu$plain  \c";echo -e "虛擬化:$blue$vi$plain  \c";echo -e "BBR算法:$blue$bbr$plain"
v4v6
if [[ "$v6" == "2a09"* ]]; then
w6="【WARP】"
fi
if [[ "$v4" == "104.28"* ]]; then
w4="【WARP】"
fi
rpip=$(sed 's://.*::g' /etc/s-box/sb.json 2>/dev/null | jq -r '.outbounds[0].domain_strategy')
[[ -z $v4 ]] && showv4='IPV4地址丟失，請切換至IPV6或者重裝Sing-box' || showv4=$v4$w4
[[ -z $v6 ]] && showv6='IPV6地址丟失，請切換至IPV4或者重裝Sing-box' || showv6=$v6$w6
if [[ $rpip = 'prefer_ipv6' ]]; then
v4_6="IPV6優先出站($showv6)"
elif [[ $rpip = 'prefer_ipv4' ]]; then
v4_6="IPV4優先出站($showv4)"
elif [[ $rpip = 'ipv4_only' ]]; then
v4_6="僅IPV4出站($showv4)"
elif [[ $rpip = 'ipv6_only' ]]; then
v4_6="僅IPV6出站($showv6)"
fi
if [[ -z $v4 ]]; then
vps_ipv4='無IPV4'      
vps_ipv6="$v6"
elif [[ -n $v4 &&  -n $v6 ]]; then
vps_ipv4="$v4"    
vps_ipv6="$v6"
else
vps_ipv4="$v4"    
vps_ipv6='無IPV6'
fi
echo -e "本地IPV4地址：$blue$vps_ipv4$w4$plain   本地IPV6地址：$blue$vps_ipv6$w6$plain"
if [[ -n $rpip ]]; then
echo -e "代理IP優先級：$blue$v4_6$plain"
fi
if [[ x"${release}" == x"alpine" ]]; then
status_cmd="rc-service sing-box status"
status_pattern="started"
else
status_cmd="systemctl status sing-box"
status_pattern="active"
fi
if [[ -n $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f '/etc/s-box/sb.json' ]]; then
echo -e "Sing-box狀態：$blue運行中$plain"
elif [[ -z $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f '/etc/s-box/sb.json' ]]; then
echo -e "Sing-box狀態：$yellow未啓動，選擇10查看日誌並反饋，建議切換正式版內核或卸載重裝腳本$plain"
else
echo -e "Sing-box狀態：$red未安裝$plain"
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
if [ -f '/etc/s-box/sb.json' ]; then
showprotocol
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
readp "請輸入數字【0-16】:" Input
case "$Input" in  
 1 ) instsllsingbox;;
 2 ) unins;;
 3 ) changeserv;;
 4 ) changeport;;
 5 ) changefl;;
 6 ) stclre;;
 7 ) upsbyg;; 
 8 ) upsbcroe;;
 9 ) clash_sb_share;;
10 ) sblog;;
11 ) bbr;;
12 ) acme;;
13 ) cfwarp;;
14 ) inssbwpph;;
15 ) wgcfgo && sbshare;;
16 ) sbsm;;
 * ) exit 
esac
