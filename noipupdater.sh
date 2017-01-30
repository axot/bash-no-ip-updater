#!/opt/bin/bash

# Copyright (C) 2016 Matthew D. Mower, Zheng SHAO
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Defines

url_encode() {
    echo $(python -c "import urllib; print urllib.quote('''$1''')")
}

CONFIGFILE="$( cd "$( dirname "$0" )" && pwd )/config"

if [ -e $CONFIGFILE ]; then
    source $CONFIGFILE
else
    echo "Config file not found."
    exit 1
fi

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
   echo "USERNAME or PASSWORD has not been set in the config file."
   exit 1
fi

USERAGENT="Bash No-IP Updater/0.9 "$USERNAME

#USERNAME=$(echo -ne $USERNAME | od -A n -t x1 | tr -d '\n' | sed 's/ /%/g')
#PASSWORD=$(echo -ne $PASSWORD | od -A n -t x1 | tr -d '\n' | sed 's/ /%/g')
USERNAME=$(url_encode $USERNAME | tr -d '\n')
PASSWORD=$(url_encode $PASSWORD | tr -d '\n')

if [ ! -d $LOGDIR ]; then
    mkdir -p $LOGDIR
    if [ $? -ne 0 ]; then
        echo "Log directory could not be created or accessed."
        exit 1
    fi
fi

LOGFILE=${LOGDIR%/}/noip.log
IPFILE=${LOGDIR%/}/last_ip
if [ ! -e $LOGFILE ] || [ ! -e $IPFILE ]; then
    touch $LOGFILE $IPFILE
    if [ $? -ne 0 ]; then
        echo "Log files could not be created. Is the log directory writable?"
        exit 1
    fi
elif [ ! -w $LOGFILE ] || [ ! -w $IPFILE ]; then
    echo "Log files not writable."
    exit 1
fi

# Functions

# IP Validator
# http://www.linuxjournal.com/content/validating-ip-address-bash-script
function valid_ip() {
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

# Program

NOW=$(date '+%s')

if [ -e $LOGFILE ] && tail -n1 $LOGFILE | grep -q -m1 '(abuse)'; then
    echo "This account has been flagged for abuse. You need to contact noip.com to resolve"
    echo "the issue. Once you have confirmed your account is in good standing, remove the"
    echo "log line containing (abuse) from:"
    echo "  $LOGFILE"
    echo "Then, re-run this script."
    exit 1
fi

GET_IP_URLS[0]="http://ident.me"
GET_IP_URLS[1]="http://wgetip.com"
GET_IP_URLS[2]="http://icanhazip.com"
GET_IP_URLS[3]="http://wtfismyip.com/text"
GET_IP_URLS[4]="http://ipecho.net/plain"

GIP_INDEX=0
while [ -n "${GET_IP_URLS[$GIP_INDEX]}" ] && ! valid_ip $NEWIP; do
    NEWIP=$(curl -s ${GET_IP_URLS[$GIP_INDEX]} | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}')
    let GIP_INDEX++
done

if ! valid_ip $NEWIP; then
    LOGDATE="[$(date +'%Y-%m-%d %H:%M:%S')]"
    LOGLINE="Could not find current IP"
    echo $LOGLINE
    echo "$LOGDATE $LOGLINE" >> $LOGFILE
    /sbin/ddns_custom_updated 0
    exit 1
fi

RESPONSE=$(curl -s -k --user-agent "$USERAGENT" "https://$USERNAME:$PASSWORD@dynupdate.no-ip.com/nic/update?hostname=$HOST&myip=$NEWIP")
RESPONSE_A=$(echo $RESPONSE | head -1 | awk '{ print $1 }')

case $RESPONSE_A in
    "good")
        RESPONSE_B=$(echo $RESPONSE | awk '{ print $2 }')
        LOGLINE="(good) DNS hostname(s) successfully updated to $RESPONSE_B."
        ;;
    "nochg")
        RESPONSE_B=$(echo $RESPONSE | awk '{ print $2 }')
        LOGLINE="(nochg) IP address is current: $RESPONSE_B; no update performed."
        ;;
    "nohost")
        LOGLINE="(nohost) Hostname supplied does not exist under specified account. Revise config file."
        ;;
    "badauth")
        LOGLINE="(badauth) Invalid username password combination."
        ;;
    "badagent")
        LOGLINE="(badagent) Client disabled - No-IP is no longer allowing requests from this update script."
        ;;
    "!donator")
        LOGLINE="(!donator) An update request was sent including a feature that is not available."
        ;;
    "abuse")
        LOGLINE="(abuse) Username is blocked due to abuse."
        ;;
    "911")
        LOGLINE="(911) A fatal error on our side such as a database outage. Retry the update in no sooner than 30 minutes."
        ;;
    *)
        LOGLINE="(error) Could not understand the response from No-IP. The DNS update server may be down."
        ;;
esac

LOGDATE="[$(date +'%Y-%m-%d %H:%M:%S')]"

echo "IP: $NEWIP"
echo $NEWIP > $IPFILE
echo $LOGLINE
echo "$LOGDATE $LOGLINE" >> $LOGFILE

/sbin/ddns_custom_updated 1
exit 0
