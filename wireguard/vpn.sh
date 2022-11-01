#!/bin/sh

set -x

default_gtw=$(ip route show default | awk '/default/ {print $3}')
default_interface=$(ip route show default | awk '/default/ {print $5}')
dns_server=10.200.200.2

if [[ $2 == "all_traffic" ]]
then
  sed -iE 's/^AllowedIPs = 10.200.200/#AllowedIPs = 10.200.200/g' /etc/wireguard/wg0.conf
  sed -iE 's/^#AllowedIPs = 0.0.0.0/AllowedIPs = 0.0.0.0/g' /etc/wireguard/wg0.conf
else
  sed -iE 's/^#AllowedIPs = 10.200.200/AllowedIPs = 10.200.200/g' /etc/wireguard/wg0.conf
  sed -iE 's/^AllowedIPs = 0.0.0.0/#AllowedIPs = 0.0.0.0/g' /etc/wireguard/wg0.conf
fi

wg-quick down wg0
if [[ $1 == "start" ]]
then
  wg-quick up wg0
fi

#systemd-resolve --interface ${default_interface} --set-dns ${dns_server} --set-domain lan

if [[ ${default_gtw} == 192.168.* ]] && [[ $1 == "start" ]]
then
  ip route add 192.168.0.0/16 dev ${default_interface} via ${default_gtw}
elif [[ ${default_gtw} == 192.168.* ]] && [[ $1 == "stop" ]]
then
  ip route del 192.168.0.0/16 dev ${default_interface} via ${default_gtw}
fi

