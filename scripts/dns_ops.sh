#!/bin/bash

# DNS records management tool for Bind9
# Supports multiple Keys and Zone Files
# By Dong Guo from heylinux.com

base_dir="/var/named"
server_ipaddr="172.16.2.221"
domain="heylinux.com"
sub_domains=".cn|.jp|.us"
dnsaddfile="${base_dir}/dnsadd"

declare -A private_keys_dict=(
["A"]="Kheylinux.com.+178+63254.private"
["CNAME"]="Kheylinux.com.+157+59510.private"
["PTR"]="Kheylinux.com.+165+98364.private"
)

function check_root(){
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 1>&2
    exit 1
  fi
}

function print_help(){
  echo "Usage: ${0} -t A|CNAME|PTR -u add|del -n servername -p record_value [-s ttl_seconds]"
  echo "Examples:"
  echo "${0} -t A -u add -n ns1 -p 172.16.2.222"
  echo "${0} -t A -u del -n ns1 -p 172.16.2.222"
  echo ""
  echo "${0} -t A -u add -n ns1.cn -p 172.16.2.223"
  echo "${0} -t A -u add -n ns1.jp -p 172.16.2.224"
  echo "${0} -t A -u add -n ns1.us -p 172.16.2.225"
  echo "${0} -t A -u del -n ns1.cn -p 172.16.2.223"
  echo ""
  echo "${0} -t CNAME -u add -n ns3 -p ns1.heylinux.com"
  echo "${0} -t CNAME -u add -n ns3 -p ns1.heylinux.com -s 30"
  echo "${0} -t CNAME -u del -n ns3 -p ns1.heylinux.com"
  echo ""
  echo "${0} -t CNAME -u add -n ns3.cn -p ns1.cn.heylinux.com"
  echo "${0} -t CNAME -u del -n ns3.cn -p ns1.cn.heylinux.com"
  echo ""
  echo "${0} -t PTR -u add -n 172.16.2.222 -p ns1.heylinux.com"
  echo "${0} -t PTR -u del -n 172.16.2.222 -p ns1.heylinux.com"
  echo ""
  echo "${0} -t PTR -u add -n 172.16.2.223 -p ns1.cn.heylinux.com"
  echo "${0} -t PTR -u del -n 172.16.2.223 -p ns1.cn.heylinux.com"
  exit 1
}

function check_servername(){
  echo $servername | grep -wq ${domain}
  if [[ $? -eq 0 ]]; then
    hostname=$(echo $servername | sed s/.${domain}//g)
    echo "ERROR: '${servername}' is malformed. Servername should be just '${hostname}' without the '${domain}'"
    exit 1
  fi
}

function check_fqdn(){
  echo $record_value | grep -q '\.'
  if [[ $? -ne 0 ]]; then
    echo "ERROR: '${record_value}' is malformed. Should be a FQDN"
    exit 1
  fi
}

function check_prereq(){
  # Check if the prerequisite is satisfied, such as duplicate and nonexistent
  if [[ $action == "add" ]]; then
    if [[ $record_type == "PTR" ]]; then
      echo "prereq nxrrset ${servername}.${domain} ${record_type} ${record_value}" >> ${dnsaddfile}
    else
      echo "prereq nxdomain ${servername}.${domain}" >> ${dnsaddfile}
    fi
  fi
  if [[ $action == "delete" ]]; then
    echo "prereq yxrrset ${servername}.${domain} ${record_type} ${record_value}" >> ${dnsaddfile}
  fi
}

function update_record(){
  if [[ -z "${ttl_seconds}" ]]; then
    ttl_seconds=86400
  fi

  echo "server ${server_ipaddr}" >> ${dnsaddfile}

  sub_domain_string=$(echo ${sub_domains} | sed s/[.]/'\\\.'/g)
  eval_command="echo \"${servername}\" | grep -Erq '${sub_domain_string}'"
  if $(eval ${eval_command}); then
    sub_domain=$(echo ${servername} | awk -F '.' '{print $NF}')
    zone=${sub_domain}.${domain}
  else
    zone=${domain}
  fi
  echo "zone ${zone}" >> ${dnsaddfile}

  check_prereq
  echo "update $action ${servername}.${domain} ${ttl_seconds} ${record_type} ${record_value}" >> ${dnsaddfile}
  echo "send" >> ${dnsaddfile}

  echo "update $action ${servername}.${domain} ${ttl_seconds} ${record_type} ${record_value}"

  private_key=${private_keys_dict["${record_type}"]}
  /usr/bin/nsupdate -k ${private_key} ${dnsaddfile}
  if [[ $? -eq 0 ]]; then
    echo "OK. Successful"
  else
    if [[ $action == "add" ]]; then
      echo "ERROR: Failed because duplicate record"
    elif [[ $action == "delete" ]]; then
      echo "ERROR: Failed because nonexistent/protected record"
    fi
    exit $?
  fi

  # Write DNS records into zone file immediately, by default it does every 15 minutes
  #/usr/sbin/rndc freeze ${zone}
  #/usr/sbin/rndc reload ${zone}
  #/usr/sbin/rndc thaw ${zone}
}

check_root
while getopts "t:u:n:p:s:" opts; do
  case "$opts" in
    "t")
      record_type=$OPTARG
      ;;
    "u")
      action=$OPTARG
      ;;
    "n")
      servername=$OPTARG
      ;;
    "p")
      record_value=$OPTARG
      ;;
    "s")
      ttl_seconds=$OPTARG
      ;;
    *)
      print_help
      ;;
  esac
done

if [[ -z "$record_type" ]] || [[ -z "$action" ]] || [[ -z "$servername" ]] || [[ -z "$record_value" ]]; then
  print_help
else
  > ${dnsaddfile}
  case "$action" in
    "add")
      action=add
      ;;
    "del")
      action=delete
      ;;
    *)
      print_help
      ;;
  esac
  case "$record_type" in
    "A")
      check_servername
      update_record
      ;;
    "CNAME")
      check_servername
      check_fqdn
      update_record
      ;;
    "PTR")
      check_fqdn
      a=$(echo $servername |cut -d. -f1 |grep -Ev '[a-z]|[A-Z]')
      b=$(echo $servername |cut -d. -f2 |grep -Ev '[a-z]|[A-Z]')
      c=$(echo $servername |cut -d. -f3 |grep -Ev '[a-z]|[A-Z]')
      d=$(echo $servername |cut -d. -f4 |grep -Ev '[a-z]|[A-Z]')
      if [[ -z "$a" ]] || [[ -z "$b" ]] || [[ -z "$c" ]] || [[ -z "$d" ]]; then
        echo "ERROR: '${servername}' is malformed. Should be a IP address"
      else
        domain=$c.$b.$a.in-addr.arpa
        servername=$d
        if [[ ! -f ${base_dir}/${domain}.zone ]]; then
          echo "ERROR: ${base_dir}/${domain}.zone does not exist"
          exit 1
        else
          update_record
        fi
      fi
      ;;
    *)
      print_help
      ;;
  esac
fi
