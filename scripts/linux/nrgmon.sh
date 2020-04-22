#!/bin/bash

#######################################################################
# Copyright (c) 2020
# All rights reserved.
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
#
# Desc:   NRG Monitor Toolset: Set of tools to monitor and manage NRG
#         Core Node, the reward received and notify the user via email
#         SMS and Social Media channels. Currently, Discord and Telegram
#         are the social media channels supported.
# 
# Version:
#   1.0.0  20200416  ZAlam Initial Script
#
# Set script version
NRGMONVER=1.0.1

 : '
# Run this file

```
  bash -ic "$(wget -4qO- -o- raw.githubusercontent.com/energicryptocurrency/energi3-provisioning/master/scripts/linux/nrgmon.sh)" ; source ~/.bashrc
```
'

 # Simple guide
 # https://imgur.com/a/B8RMhHV
 
 ### Drop mn_rewards table after sending notice
 ### SQL_QUERY "DROP TABLE IF EXISTS mn_rewards;"
 
 ###
 ### sqlite3 -header -csv /var/multi-masternode-data/nrgbot/nrgmon.db "select * from mn_rewards;" > $HOME/etc/mn_rewards.csv
 ### sqlite3 -header -csv /var/multi-masternode-data/nrgbot/nrgmon.db "select * from stake_rewards;" > $HOME/etc/stake_rewards.csv
 ###
 
 ###
 ### SQL_QUERY "SELECT * FROM stake_rewards WHERE blockNumber >= ${LASTCHKBLOCK} AND < ${CURRENTBLKNUM} ;"
 ### SQL_QUERY "SELECT * FROM mn_rewards WHERE blockNumber BETWEEN ${STARTMNBLK} AND ${ENDMNBLK} ;"
 ###
 
 ###
 ### SELECT DATETIME(rewardTime,'unixepoch') FROM stake_rewards WHERE blockNumber BETWEEN ${LASTCHKBLOCK} and ${CURRENTBLKNUM};
 ### SELECT DATETIME(rewardTime,'unixepoch'),blockNumber,mnBlockReward FROM mn_rewards WHERE blockNumber BETWEEN ${STARTMNBLK} and ${ENDMNBLK};
 ###
 
 # Load parameters from external conf file
 if [[ -f /var/multi-masternode-data/nrgbot/nrgmon.conf ]]
 then
  . /var/multi-masternode-data/nrgbot/nrgmon.conf
 else
  SENDNOTICE=N
 fi

 # Which Timezone you want to see notices
 export TZ=UTC

 # Temp Files
 TOMAILFILE=/tmp/reward_email.txt
 TOSMSFILE=/tmp/reward_sms.txt
 
 
 function CTRL_C () {
  stty sane 2>/dev/null
  printf "\e[0m"
  echo
  exit

}

 trap CTRL_C INT

 # Define simple variables.
 stty sane 2>/dev/null
 arg1="${1}"
 arg2="${2}"
 arg3="${3}"
 RE='^[0-9]+$'
 DISCORD_WEBHOOK_USERNAME_DEFAULT='Energi Node Monitor'
 DISCORD_WEBHOOK_AVATAR_DEFAULT='https://i.imgur.com/8WHSSa7s.jpg'
 DISCORD_TITLE_LIMIT=266
 
 # NRG Parameters
 STAKEAMT="2.28"
 MNMINRWD="0.914"
 NRGAPI="https://explorer.energi.network/api"
 
 # Set variables
 MNTOTALNRG=0
 USRNAME=$( find /home -name nodekey  2>&1 | grep -v "Permission denied" | awk -F\/ '{print $3}' )
 export PATH=$PATH:/home/${USRNAME}/energi3/bin
 RWDDATA="/home/${USRNAME}/etc/reward_data.csv"
 LOGFILE="/home/${USRNAME}/log/nrg_monitor.log"
 
 # Set colors
 BLUE=$( tput setaf 4 )
 RED=$( tput setaf 1 )
 GREEN=$( tput setaf 2 )
 YELLOW=$( tput setaf 2 )
 NC=$( tput sgr0 )
 
 # Script can be run as root or nrgstaker
 if [[ $EUID = 0 ]]
  then
    SUDO=""
  else
    ISSUDOER=`getent group sudo | grep ${USRNAME}`
    if [ ! -z "${ISSUDOER}" ]
    then
      SUDO='sudo'
    else
      echo "User ${USRNAME} does not have sudo permissions."
      echo "Run ${BLUE}sudo ls -l${NC} to set permissions if you know the user ${USRNAME} has sudo previlidges"
      echo "and then rerun the script"
      echo "Exiting script..."
      sleep 3
      exit 0
    fi
  fi

 
 # Set datadir
 DATADIR=$( ps -ef | grep datadir | grep -v "grep datadir" | grep -v "color" )
 DATADIR=$( echo $DATADIR | awk -F'datadir' '{print $2}' | awk -F' ' '{print $1}' )
 
 # Attach command
 COMMAND="energi3 ${ARG} --datadir ${DATADIR} attach --exec"

 # debug arg.
 DEBUG_OUTPUT=0
 if [[ "${arg1}" == 'debug' ]]
then
  DEBUG_OUTPUT=1
  set -x
fi
 if [[ "${arg2}" == 'debug' ]]
then
  DEBUG_OUTPUT=1
  set -x
fi
 if [[ "${arg3}" == 'debug' ]]
then
  DEBUG_OUTPUT=1
  set -x
fi

 # test arg.
 TEST_OUTPUT=0
 if [[ "${arg1}" == 'test' ]]
then
  TEST_OUTPUT=1
fi
 if [[ "${arg2}" == 'test' ]]
then
  TEST_OUTPUT=1
fi
 if [[ "${arg3}" == 'test' ]]
then
  TEST_OUTPUT=1
fi

 # Set defaults.
 # RAM.
 if [[ -z "${LOW_MEM_WARN_MB}" ]]
then
  LOW_MEM_WARN_MB=850
fi
 if [[ -z "${LOW_MEM_WARN_PERCENT}" ]]
then
  LOW_MEM_WARN_PERCENT=2
fi
 if [[ -z "${LOW_MEM_ERROR_MB}" ]]
then
  LOW_MEM_ERROR_MB=725
fi
 if [[ -z "${LOW_MEM_ERROR_PERCENT}" ]]
then
  LOW_MEM_ERROR_PERCENT=1
fi
 # SWAP.
 if [[ -z "${LOW_SWAP_ERROR_MB}" ]]
then
  LOW_SWAP_ERROR_MB=512
fi
 if [[ -z "${LOW_SWAP_WARN_MB}" ]]
then
  LOW_SWAP_WARN_MB=1024
fi
 # Hard Drive Space.
 if [[ -z "${LOW_HDD_ERROR_MB}" ]]
then
  LOW_HDD_ERROR_MB=512
fi
LOW_HDD_ERROR_KB=$( echo "${LOW_HDD_ERROR_MB} * 1024" | bc )
 if [[ -z "${LOW_HDD_WARN_MB}" ]]
then
  LOW_HDD_WARN_MB=1536
fi
LOW_HDD_WARN_KB=$( echo "${LOW_HDD_WARN_MB} * 1024" | bc )
 if [[ -z "${LOW_HDD_BOOT_ERROR_MB}" ]]
then
  LOW_HDD_BOOT_ERROR_MB=64
fi
LOW_HDD_BOOT_ERROR_KB=$( echo "${LOW_HDD_BOOT_ERROR_MB} * 1024" | bc )
 if [[ -z "${LOW_HDD_BOOT_WARN_MB}" ]]
then
  LOW_HDD_BOOT_WARN_MB=128
fi
LOW_HDD_BOOT_WARN_KB=$( echo "${LOW_HDD_BOOT_WARN_MB} * 1024" | bc )
 # CPU Load.
 if [[ -z "${CPU_LOAD_ERROR}" ]]
then
  CPU_LOAD_ERROR=4
fi
 if [[ -z "${CPU_LOAD_WARN}" ]]
then
  CPU_LOAD_WARN=2
fi

 # APT update/upgrade
 sudo DEBIAN_FRONTEND=noninteractive apt-get update
 sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -yq
 
 # Get sqlite.
 if [ ! -x "$( command -v sqlite3 )" ]
 then
   sudo DEBIAN_FRONTEND=noninteractive apt-get install -yq sqlite3
 fi
 # Get jq.
 if [ ! -x "$( command -v jq)" ]
then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -yq jq
fi
 # Get ntpdate.
 if [ ! -x "$( command -v ntpdate )" ]
then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -yq ntpdate
fi
 # Get debsums.
 if [ ! -x "$( command -v debsums )" ]
then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -yq debsums
fi
 # Get rkhunter
 if [ ! -x "$( command -v rkhunter )" ]
then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -yq rkhunter
fi

 # Run a sqlite query.
 SQL_QUERY () {
  if [[ ! -d /var/multi-masternode-data/nrgbot ]]
  then
    sudo mkdir -p /var/multi-masternode-data/nrgbot
  fi
  sudo sqlite3 -batch /var/multi-masternode-data/nrgbot/nrgmon.db "${1}"
}

 # Formatted sqlite report
 SQL_REPORT () {
 sqlite3 -header -column -separator ROW /var/multi-masternode-data/nrgbot/nrgmon.db "${1}"
}

 # Create tables if they do not exist.
 # Key Value table.
 SQL_QUERY "CREATE TABLE IF NOT EXISTS variables (
 key TEXT PRIMARY KEY,
 value TEXT NOT NULL
);"

 # Insert seed data; give poll 5 blocks from current
 CURRENTBLKNUM=$( ${COMMAND} "nrg.blockNumber" 2>/dev/null | jq -r '.' )
 CURRENTBLKNUM=$( echo ${CURRENTBLKNUM} - 5 | bc -l )
 SQL_QUERY "INSERT OR IGNORE INTO variables values ( 'last_block_checked', '${CURRENTBLKNUM}' );"

 # System logs.
 SQL_QUERY "CREATE TABLE IF NOT EXISTS system_log (
  name TEXT PRIMARY KEY,
  start_time INTEGER ,
  last_ping_time INTEGER ,
  message TEXT
);"

 # Daemon logs.
 SQL_QUERY "CREATE TABLE IF NOT EXISTS node_log (
  conf_loc TEXT,
  type TEXT,
  start_time INTEGER ,
  last_ping_time INTEGER ,
  message TEXT,
  PRIMARY KEY (conf_loc, type)
);"

 # Staking rewards
 SQL_QUERY "CREATE TABLE IF NOT EXISTS stake_rewards (
 stakeAddress TEXT,
 rewardTime INTEGER,
 blockNum INTEGER,
 reward INTEGER,
 balance REAL,
 nrgPrice REAL,
 PRIMARY KEY (stakeAddress, blockNum)
);"

 # Masternode rewards
 SQL_QUERY "CREATE TABLE IF NOT EXISTS mn_rewards (
 mnAddress TEXT,
 rewardTime INTEGER,
 blockNum INTEGER,
 reward INTEGER,
 balance REAL,
 nrgPrice REAL,
 PRIMARY KEY (mnAddress, blockNum)
);"

 SQL_QUERY "CREATE TABLE IF NOT EXISTS mn_blocks (
 mnAddress TEXT PRIMARY KEY, 
 mnBlocksReceived TEXT, 
 startMnBlk INTEGER,
 endMnBlk INTEGER,
 mnTotalReward INTEGER
);"

 # Daemon_bin_name URL_to_logo Bot_name
 DAEMON_BIN_LUT="
energi3 https://s2.coinmarketcap.com/static/img/coins/128x128/3218.png Energi Monitor
"

 # Daemon_bin_name minimum_balance_to_stake staking_reward mn_reward confirmations cooloff_seconds networkhashps_multiplier ticker_name blocktime_seconds
 DAEMON_BALANCE_LUT="
energi3 1 2.28 0.914 101 3600 0.000001 NRG 60
"

 # Add timestamp to Log
 function log {
    echo "[$(date --rfc-3339=seconds)]: $*" >> $LOGFILE
}

 # Convert seconds to days, hours, minutes, seconds.
 DISPLAYTIME () {
  # Round up the time.
  local T=0
  T=$( printf '%.*f\n' 0 "${1}" )
  local D=$(( T/60/60/24 ))
  local H=$(( T/60/60%24 ))
  local M=$(( T/60%60 ))
  local S=$(( T%60 ))
  (( D > 0 )) && printf '%d days ' "${D}"
  (( H > 0 )) && printf '%d hr ' "${H}"
  (( M > 0 )) && printf '%d min ' "${M}"
  (( S > 0 )) && printf '%d sec ' "${S}"
}

 # Create a service that runs every minute.
 INSTALL_NRGMON_SERVICE () {
  if [[ -f "${HOME}/energi3/bin/nrgmon.sh" ]]
  then
    sudo cp "${HOME}/energi3/bin/nrgmon.sh" /var/multi-masternode-data/nrgbot/nrgmon.sh
  else
    COUNTER=0
    sudo rm -f /var/multi-masternode-data/nrgbot/nrgmon.sh
    while [[ ! -f /var/multi-masternode-data/nrgbot/nrgmon.sh ]] || [[ $( sudo grep -Fxc " # End of the masternode monitor script." /var/multi-masternode-data/nrgbot/nrgmon.sh ) -eq 0 ]]
    do
      sudo rm -f /var/multi-masternode-data/nrgbot/nrgmon.sh
      echo "Downloading Masternode Setup Script."
      sudo wget -q4o- https://raw.githubusercontent.com/energicryptocurrency/energi3-provisioning/master/scripts/linux/nrgmon.sh -O /var/multi-masternode-data/nrgbot/nrgmon.sh
      sudo chmod 755 /var/multi-masternode-data/nrgbot/nrgmon.sh
      COUNTER=$(( COUNTER+1 ))
      if [[ "${COUNTER}" -gt 3 ]]
      then
        echo
        echo "Download of masternode monitor script failed."
        echo
        exit 1
      fi
    done
  fi

  cat << SYSTEMD_CONF | sudo tee /etc/systemd/system/nrgmon.service >/dev/null
[Unit]
Description=Core Node Monitor
After=syslog.target network.target

[Service]
SyslogIdentifier=cftimer-energi3-node-monitor
Type=oneshot
Restart=no
RestartSec=5
UMask=0027
ExecStart=/bin/bash -i /var/multi-masternode-data/nrgbot/nrgmon.sh cron

[Install]
WantedBy=multi-user.target
SYSTEMD_CONF

  cat << SYSTEMD_CONF | sudo tee /etc/systemd/system/nrgmon.timer >/dev/null
[Unit]
Description=Run Core Node Monitor Every 10 Minute
Requires=nrgmon.service

[Timer]
Unit=nrgmon.service
OnBootSec=60
OnUnitActiveSec=10 m

[Install]
WantedBy=timers.target
SYSTEMD_CONF

  cat << SYSTEMD_CONF | sudo tee /etc/systemd/system/nrgmon.slice >/dev/null
[Unit]
Description=Limited resources Slice
DefaultDependencies=no
Before=slices.target

[Slice]
CPUQuota=50%
MemoryLimit=1.0G
SYSTEMD_CONF

  echo "Reload systemclt Service"
  sudo systemctl daemon-reload
  echo "Enable nrgmon Service"
  sudo systemctl enable nrgmon.timer --now
  sudo systemctl start nrgmon.timer
}

 # Send the data to discord via webhook.
 DISCORD_WEBHOOK_SEND () {
(
  local SERVER_ALIAS
  local SHOW_IP
  local _PAYLOAD
  local IP_ADDRESS=''

  local URL="${1}"
  local DESCRIPTION="${2}"
  local TITLE="${3}"
  local DISCORD_WEBHOOK_USERNAME="${4}"
  local DISCORD_WEBHOOK_AVATAR="${5}"
  local DISCORD_WEBHOOK_COLOR="${6}"
  local SERVER_INFO="${7}"

  # Username to show.
  if [[ -z "${DISCORD_WEBHOOK_USERNAME}" ]]
  then
    DISCORD_WEBHOOK_USERNAME="${DISCORD_WEBHOOK_USERNAME_DEFAULT}"
  fi
  # Avatar to show.
  if [[ -z "${DISCORD_WEBHOOK_AVATAR}" ]]
  then
    DISCORD_WEBHOOK_AVATAR="${DISCORD_WEBHOOK_AVATAR_DEFAULT}"
  fi

  if [[ -z "${SERVER_INFO}" ]]
  then
    SERVER_INFO=$( date -Ru )
    # Show Server Alias.
    SERVER_ALIAS=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'server_alias';" )
    if [[ -z "${SERVER_ALIAS}" ]]
    then
      SERVER_ALIAS=$( hostname )
    fi
    if [[ ! -z "${SERVER_ALIAS}" ]]
    then
      SERVER_INFO="${SERVER_INFO}
- ${SERVER_ALIAS}"
    fi

    # Show IP Address.
    SHOW_IP=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'show_ip';" )
    if [[ "${SHOW_IP}" -gt 0 ]]
    then
      IP_ADDRESS=$( hostname -i )
    fi
    if [[ ! -z "${IP_ADDRESS}" ]]
    then
      SERVER_INFO="${SERVER_INFO}
- ${IP_ADDRESS}"
    fi
  fi

  # Replace new line with \n
  SERVER_INFO=$( echo "${SERVER_INFO}" | awk '{printf "%s\\n", $0}' )
  TITLE=$( echo "${TITLE}" | tr '\n' ' ' )

  ALT_DESC=''
  while read -r LINE
  do
    CURRENT_CHAR_COUNT=$( echo "${ALT_DESC}" | tail -n 1 | wc -c )
    NEW_LINE_CHAR_COUNT=$( echo "${LINE}\n " | wc -c )
    NEW_TOTAL=$(( CURRENT_CHAR_COUNT + NEW_LINE_CHAR_COUNT ))
    if [[ "${NEW_TOTAL}" -lt "${DISCORD_TITLE_LIMIT}" ]]
    then
      ALT_DESC="${ALT_DESC}${LINE}\n"
    else
      ALT_DESC="${ALT_DESC}
${LINE}\n"
    fi
  done <<< "${DESCRIPTION}"

  # Split up the description into mutiple embeds.
  LINE_COUNT=$( echo "${ALT_DESC}" | wc -l )
  COUNTER=0
  EMBEDS='['
  while read -r LINE
  do
    COUNTER=$(( COUNTER + 1 ))
    if [[ ! -z "${LINE}" ]]
    then
      EMBEDS="${EMBEDS}{
      \"color\": ${DISCORD_WEBHOOK_COLOR},
      \"title\": \"${LINE}\""
    fi
    if [[ "${COUNTER}" -lt "${LINE_COUNT}" ]]
    then
      EMBEDS="${EMBEDS}
      },
"
    else
      EMBEDS="${EMBEDS},
      \"description\": \"${SERVER_INFO}\"
      }"
    fi
  done <<< "${ALT_DESC}"
  EMBEDS="${EMBEDS}]"

  # Build HTTP POST.
  _PAYLOAD=$( cat << PAYLOAD
{
  "username": "${DISCORD_WEBHOOK_USERNAME} - ${SERVER_ALIAS}",
  "avatar_url": "${DISCORD_WEBHOOK_AVATAR}",
  "content": "**${TITLE}**",
  "embeds": ${EMBEDS}
}
PAYLOAD
)

  # Do the post.
  OUTPUT=$( curl -H "Content-Type: application/json" -s -X POST "${URL}" -d "${_PAYLOAD}" | sed '/^[[:space:]]*$/d' )
  if [[ ! -z "${OUTPUT}" ]]
  then
    # Wait if we got throttled.
    MS_WAIT=$( echo "${OUTPUT}" | jq -r '.retry_after' 2>/dev/null )
    if [[ ! -z "${MS_WAIT}" ]]
    then
      SECONDS_WAIT=$( printf "%.1f\n" "$( echo "scale=3;${MS_WAIT}/1000" | bc -l )" )
      SECONDS_WAIT=$( echo "${SECONDS_WAIT} + 0.1" | bc -l )
      sleep "${SECONDS_WAIT}"
      OUTPUT=$( curl -H "Content-Type: application/json" -s -X POST "${URL}" -d "${_PAYLOAD}" | sed '/^[[:space:]]*$/d' )
    fi
  fi
  # If only errors get a return value.
  if [[ ! -z "${OUTPUT}" ]]
  then
    echo "Discord Error"
    _PAYLOAD=$( echo "${_PAYLOAD}" | tr -d \' )
    echo "curl -H \"Content-Type: application/json\" -v ${URL} -d '${_PAYLOAD}'"
    echo "Output:"
    echo "${OUTPUT}" | jq '.'
    echo "Payload:"
    echo "${_PAYLOAD}"
    echo "-"
  fi
)
}

 # Get the webhook url and test to make sure it works.
 DISCORD_WEBHOOK_URL_PROMPT () {
  # Title of this webhook.
  TEXT_A="${1}"
  # Url of the existing webhook.
  DISCORD_WEBHOOK_URL="${2}"
  while :
  do
    echo
    echo -en "${TEXT_A}s webhook url: \e[3m"
    read -r -e -i "${DISCORD_WEBHOOK_URL}" input
    printf "\e[0m"
    DISCORD_WEBHOOK_URL="${input:-${DISCORD_WEBHOOK_URL}}"
    if [[ ! -z "${DISCORD_WEBHOOK_URL}" ]]
    then
      TOKEN=$( wget -qO- -o- "${DISCORD_WEBHOOK_URL}" | jq -r '.token' )
      if [[ -z "${TOKEN}" ]]
      then
        echo "Given URL is not a webhook."
        echo
        echo -n 'Get Webhook URL: Your personal server (press plus on left if you do not have one)'
        echo -n ' -> Right click on your server -> Server Settings -> Webhooks'
        echo -n ' -> Create Webhook -> Copy webhook url -> save'
        echo
        DISCORD_WEBHOOK_URL=''
      else
        echo "${TOKEN}"
        break
      fi
    fi
  done
  SQL_QUERY "REPLACE INTO variables (key,value) VALUES ('discord_webhook_url_${TEXT_A}','${DISCORD_WEBHOOK_URL}');"
}

 # Prompt for all webhooks that we need.
 GET_DISCORD_WEBHOOKS () {
  # Get webhook url from discord.
  echo
  echo -n 'Get Webhook URL: Your personal server (press plus on left if you do not have one)'
  echo -n ' -> text channels, general, click gear to "edit channel" -> Left side SELECT Webhooks'
  echo -n ' -> Create Webhook -> Copy webhook url -> save'
  echo
  echo "This webhook will be used for ${TEXT_A} Messages."
  echo 'You can reuse the same webhook url if you want all alerts and information'
  echo 'pings in the same channel.'

  # Errors.
  DISCORD_WEBHOOK_URL=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'discord_webhook_url_error';" )
  DISCORD_WEBHOOK_URL_PROMPT "error" "${DISCORD_WEBHOOK_URL}"
  SEND_ERROR "Test Error"

  # Warnings.
  DISCORD_WEBHOOK_URL=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'discord_webhook_url_warning';" )
  DISCORD_WEBHOOK_URL_PROMPT "warning" "${DISCORD_WEBHOOK_URL}"
  SEND_WARNING "Test Warning"

  # Info.
  DISCORD_WEBHOOK_URL=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'discord_webhook_url_information';" )
  DISCORD_WEBHOOK_URL_PROMPT "information" "${DISCORD_WEBHOOK_URL}"
  SEND_INFO "Test Info"

  # Success.
  DISCORD_WEBHOOK_URL=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'discord_webhook_url_success';" )
  DISCORD_WEBHOOK_URL_PROMPT "success" "${DISCORD_WEBHOOK_URL}"
  SEND_SUCCESS "Test Success"
}

 # Send the data to telegram via bot.
 TELEGRAM_SEND () {
(
  local SERVER_INFO
  local SHOW_IP
  local SERVER_ALIAS
  local _PAYLOAD

  local TOKEN="${1}"
  local CHAT_ID="${2}"
  local TITLE="${3}"
  local MESSAGE="${4}"
  local SERVER_INFO="${5}"

  # Translate discord emojis to telegram.
  # https://apps.timwhitlock.info/emoji/tables/unicode
  # http://www.unicode.org/emoji/charts/full-emoji-list.html
  # https://onlineutf8tools.com/convert-utf8-to-bytes
  MESSAGE=$( echo "${MESSAGE}" | \
    sed 's/:exclamation:/\xE2\x9D\x97/g' | \
    sed 's/:unlock:/\xF0\x9F\x94\x93/g' | \
    sed 's/:warning:/\xE2\x9A\xA0/g' | \
    sed 's/:blue_book:/\xF0\x9F\x93\x98/g' | \
    sed 's/:money_mouth:/\xF0\x9F\xA4\x91/g' | \
    sed 's/:moneybag:/\xF0\x9F\x92\xB0/g' | \
    sed 's/:floppy_disk:/\xF0\x9F\x92\xBE/g' | \
    sed 's/:desktop:/\xF0\x9F\x96\xA5/g' | \
    sed 's/:wrench:/\xF0\x9F\x94\xA7/g' | \
    sed 's/:watch:/\xE2\x8C\x9A/g' | \
    sed 's/:link:/\xF0\x9F\x94\x97/g' | \
    sed 's/:fire:/\xF0\x9F\x94\xA5/g' )

  TITLE=$( echo "${TITLE}" | \
    sed 's/:exclamation:/\xE2\x9D\x97/g' | \
    sed 's/:unlock:/\xF0\x9F\x94\x93/g' | \
    sed 's/:warning:/\xE2\x9A\xA0/g' | \
    sed 's/:blue_book:/\xF0\x9F\x93\x98/g' | \
    sed 's/:money_mouth:/\xF0\x9F\xA4\x91/g' | \
    sed 's/:moneybag:/\xF0\x9F\x92\xB0/g' | \
    sed 's/:floppy_disk:/\xF0\x9F\x92\xBE/g' | \
    sed 's/:desktop:/\xF0\x9F\x96\xA5/g' | \
    sed 's/:wrench:/\xF0\x9F\x94\xA7/g' | \
    sed 's/:watch:/\xE2\x8C\x9A/g' | \
    sed 's/:link:/\xF0\x9F\x94\x97/g' | \
    sed 's/:fire:/\xF0\x9F\x94\xA5/g' )

  if [[ -z "${SERVER_INFO}" ]]
  then
    SERVER_INFO=$( date -Ru )
    SHOW_IP=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'show_ip';" )
    if [[ "${SHOW_IP}" -gt 0 ]]
    then
      # shellcheck disable=SC2028
      SERVER_INFO=$( echo -ne "${SERVER_INFO}\n - " ; hostname -i )
    fi
    SERVER_ALIAS=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'server_alias';" )
    if [[ -z "${SERVER_ALIAS}" ]]
    then
      # shellcheck disable=SC2028
      SERVER_INFO=$( echo -ne "${SERVER_INFO}\n - " ; hostname )
    else
      SERVER_INFO=$( echo -ne "${SERVER_INFO}\n - ${SERVER_ALIAS}" )
    fi
  fi

  _PAYLOAD="text=<b>${TITLE}</b>
<i>${SERVER_INFO}</i>
${MESSAGE}"

  URL="https://api.telegram.org/bot$TOKEN/sendMessage"
  TELEGRAM_MSG=$( curl -s -X POST "${URL}" -d "chat_id=${CHAT_ID}&parse_mode=html" -d "${_PAYLOAD}" | sed '/^[[:space:]]*$/d' )
  IS_OK=$( echo "${TELEGRAM_MSG}" | jq '.ok' )

  if [[ "${IS_OK}" != 'true' ]]
  then
    echo "Telegram Error"
    echo "${TELEGRAM_MSG}" | jq '.'
    echo "Payload:"
    echo "${_PAYLOAD}"
    echo "-"
  fi
  # Rate limit this function.
  sleep 0.3
)
}

 # Install telegram bot.
 TELEGRAM_SETUP () {
  TOKEN=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'telegram_token';" )
  echo "Message the @botfather https://web.telegram.org/#/im?p=@BotFather"
  echo "with the following text: "
  echo "/start"
  echo "/newbot"
  echo "Then paste in the token below"
  printf "Telegram Token: \e[3m"
  read -r -e -i "${TOKEN}" -p
  printf "\e[0m"
  if [[ ! -z "${REPLY}" ]]
  then
    TOKEN="${REPLY}"
  fi

  CHAT_ID=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'telegram_chatid';" )
  if [[ -z "${CHAT_ID}" ]] || [[ "${CHAT_ID}" == 'null' ]]
  then
    while :
    do
      GET_UPDATES=$( curl -s "https://api.telegram.org/bot${TOKEN}/getUpdates" )
      IS_OK=$( echo "${GET_UPDATES}" | jq '.ok' )
      if [[ "${IS_OK}" != 'true' ]]
      then
        echo "Please message the bot."
        read -p "When done press enter or q to quit." -r
        REPLY=${REPLY,,} # tolower
        if [[ "${REPLY}" == q ]]
        then
          return 1 2>/dev/null
        fi
        sleep 1
      else
        break
      fi
    done

    while :
    do
      GET_UPDATES=$( curl -s "https://api.telegram.org/bot${TOKEN}/getUpdates" )
      CHAT_ID=$( echo "${GET_UPDATES}" | jq '.result[0].message.chat.id' 2>/dev/null )
      if [[ -z "${CHAT_ID}" ]]
      then
        echo "Please message the bot."
      else
        SQL_QUERY "REPLACE INTO variables (key,value) VALUES ('telegram_token','${TOKEN}');"
        SQL_QUERY "REPLACE INTO variables (key,value) VALUES ('telegram_chatid','${CHAT_ID}');"
        break
      fi
    done
  fi

  TITLE="Test Title"
  MESSAGE="Bot Works!"
  TELEGRAM_SEND "${TOKEN}" "${CHAT_ID}" "${TITLE}" "<pre>${MESSAGE}</pre>"
}

 # Send an error messsage to discord and telegram.
 SEND_ERROR () {
  URL=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'discord_webhook_url_error';" )
  TOKEN=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'telegram_token';" )
  CHAT_ID=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'telegram_chatid';" )

  DESCRIPTION="${1}"
  if [[ -z "${DESCRIPTION}" ]]
  then
    DESCRIPTION="Default Error Message!"
  fi
  TITLE="${2}"
  if [[ -z "${TITLE}" ]]
  then
    TITLE=":exclamation: Error :exclamation:"
  fi
  DISCORD_WEBHOOK_COLOR="${5}"
  if [[ -z "${DISCORD_WEBHOOK_COLOR}" ]]
  then
    DISCORD_WEBHOOK_COLOR=16711680
  fi
  if [[ ! -z "${6}" ]]
  then
    URL="${6}"
  fi

  SENT=0
  if [[ ! -z "${URL}" ]]
  then
    SENT=1
    DISCORD_WEBHOOK_SEND "${URL}" "${DESCRIPTION}" "${TITLE}" "${3}" "${4}" "${DISCORD_WEBHOOK_COLOR}"
  fi
  if [[ ! -z "${TOKEN}" ]] && [[ ! -z "${CHAT_ID}" ]]
  then
    SENT=1
    TELEGRAM_SEND "${TOKEN}" "${CHAT_ID}" "${TITLE}" "<code>${DESCRIPTION}</code>"
  fi
  if [[ "${SENT}" -eq 0 ]] || [[ "${DEBUG_OUTPUT}" -eq 1 ]]
  then
    echo "${TITLE}" >/dev/tty
    echo "${DESCRIPTION}" >/dev/tty
    echo "-" >/dev/tty
  fi
}

 SEND_WARNING () {
  URL=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'discord_webhook_url_warning';" )
  TOKEN=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'telegram_token';" )
  CHAT_ID=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'telegram_chatid';" )

  DESCRIPTION="${1}"
  if [[ -z "${DESCRIPTION}" ]]
  then
    DESCRIPTION="Default Warning Message."
  fi
  TITLE="${2}"
  if [[ -z "${TITLE}" ]]
  then
    TITLE=":warning: Warning :warning:"
  fi
  DISCORD_WEBHOOK_COLOR="${5}"
  if [[ -z "${DISCORD_WEBHOOK_COLOR}" ]]
  then
    DISCORD_WEBHOOK_COLOR=16776960
  fi
  if [[ ! -z "${6}" ]]
  then
    URL="${6}"
  fi

  SENT=0
  if [[ ! -z "${URL}" ]]
  then
    SENT=1
    DISCORD_WEBHOOK_SEND "${URL}" "${DESCRIPTION}" "${TITLE}" "${3}" "${4}" "${DISCORD_WEBHOOK_COLOR}"
  fi
  if [[ ! -z "${TOKEN}" ]] && [[ ! -z "${CHAT_ID}" ]]
  then
    SENT=1
    TELEGRAM_SEND "${TOKEN}" "${CHAT_ID}" "${TITLE}" "<pre>${DESCRIPTION}</pre>"
  fi
  if [[ "${SENT}" -eq 0 ]] || [[ "${DEBUG_OUTPUT}" -eq 1 ]]
  then
    echo "${TITLE}" >/dev/tty
    echo "${DESCRIPTION}" >/dev/tty
    echo "-" >/dev/tty
  fi
}

 SEND_INFO () {
  URL=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'discord_webhook_url_information';" )
  TOKEN=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'telegram_token';" )
  CHAT_ID=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'telegram_chatid';" )

  DESCRIPTION="${1}"
  if [[ -z "${DESCRIPTION}" ]]
  then
    DESCRIPTION="Default Information Message."
  fi
  TITLE="${2}"
  if [[ -z "${TITLE}" ]]
  then
    TITLE=":blue_book: Information :blue_book:"
  fi
  DISCORD_WEBHOOK_COLOR="${5}"
  if [[ -z "${DISCORD_WEBHOOK_COLOR}" ]]
  then
    DISCORD_WEBHOOK_COLOR=65535
  fi
  if [[ ! -z "${6}" ]]
  then
    URL="${6}"
  fi

  SENT=0
  if [[ ! -z "${URL}" ]]
  then
    SENT=1
    DISCORD_WEBHOOK_SEND "${URL}" "${DESCRIPTION}" "${TITLE}" "${3}" "${4}" "${DISCORD_WEBHOOK_COLOR}"
  fi
  if [[ ! -z "${TOKEN}" ]] && [[ ! -z "${CHAT_ID}" ]]
  then
    SENT=1
    TELEGRAM_SEND "${TOKEN}" "${CHAT_ID}" "${TITLE}" "<pre>${DESCRIPTION}</pre>"
  fi
  if [[ "${SENT}" -eq 0 ]] || [[ "${DEBUG_OUTPUT}" -eq 1 ]]
  then
    echo "${TITLE}" >/dev/tty
    echo "${DESCRIPTION}" >/dev/tty
    echo "-" >/dev/tty
  fi
}

 SEND_SUCCESS () {
  URL=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'discord_webhook_url_success';" )
  TOKEN=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'telegram_token';" )
  CHAT_ID=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'telegram_chatid';" )

  DESCRIPTION="${1}"
  if [[ -z "${DESCRIPTION}" ]]
  then
    DESCRIPTION="Default Success Message!"
  fi
  TITLE="${2}"
  if [[ -z "${TITLE}" ]]
  then
    TITLE=":moneybag: Success :money_mouth:"
  fi
  DISCORD_WEBHOOK_COLOR="${5}"
  if [[ -z "${DISCORD_WEBHOOK_COLOR}" ]]
  then
    DISCORD_WEBHOOK_COLOR=65535
  fi
  if [[ ! -z "${6}" ]]
  then
    URL="${6}"
  fi

  SENT=0
  if [[ ! -z "${URL}" ]]
  then
    SENT=1
    DISCORD_WEBHOOK_SEND "${URL}" "${DESCRIPTION}" "${TITLE}" "${3}" "${4}" "${DISCORD_WEBHOOK_COLOR}"
  fi
  if [[ ! -z "${TOKEN}" ]] && [[ ! -z "${CHAT_ID}" ]]
  then
    SENT=1
    TELEGRAM_SEND "${TOKEN}" "${CHAT_ID}" "${TITLE}" "<pre>${DESCRIPTION}</pre>"
  fi
  if [[ "${SENT}" -eq 0 ]] || [[ "${DEBUG_OUTPUT}" -eq 1 ]]
  then
    echo "${TITLE}" >/dev/tty
    echo "${DESCRIPTION}">/dev/tty
    echo "-" >/dev/tty
  fi
}

SEND_EMAIL () {
  # Compose Email Message
  echo "To: ${SENDTOEMAIL}" > $TOMAILFILE
  echo "From: ${SENDTOEMAIL}" >> $TOMAILFILE
  echo "Subject: NRG-${SHORTADDR} - $1 " >> $TOMAILFILE
  echo ""  >> $TOMAILFILE
  echo "Current Balance: ${CURRENTBAL} NRG" >> $TOMAILFILE
  echo "Reward Amount:   ${REWARDAMT} NRG" >> $TOMAILFILE
  echo "Market Price:    ${NRGPRICE}" >> $TOMAILFILE

  echo "" >> $TOMAILFILE
}

SEND_SMS () {
    # Compose SMS Message
    echo "To: ${SENDTOMOBILE}@${SENDTOGATEWAY}" > $TOSMSFILE
    echo "From: ${SENDTOEMAIL}" >> $TOSMSFILE
    echo "Subject: NRG-${SHORTADDR}" >> $TOSMSFILE
    echo ""  >> $TOSMSFILE
    echo "Amt Rcvd: ${REWARDAMT}" >> $TOSMSFILE

    # Send email
    log "${SHORTADDR}: Send email & SMS"
    ssmtp ${SENDTOEMAIL} < $TOMAILFILE
    ssmtp ${SENDTOMOBILE}@${SENDTOGATEWAY} < $TOSMSFILE
}

 PROCESS_MESSAGES () {
  local ERRORS=''
  local MESSAGE=''
  local NAME=${1}
  local MESSAGE_ERROR=${2}
  local MESSAGE_WARNING=${3}
  local MESSAGE_INFO=${4}
  local MESSAGE_SUCCESS=${5}
  local RECOVERED_MESSAGE_SUCCESS=${6}
  local RECOVERED_TITLE_SUCCESS=${7}
  local DISCORD_WEBHOOK_USERNAME=${8}
  local DISCORD_WEBHOOK_AVATAR=${9}


  # Get past events.
  UNIX_TIME=$( date -u +%s )
  MESSAGE_PAST=$( SQL_QUERY "SELECT start_time,last_ping_time,message FROM system_log WHERE name == '${NAME}'; " )
  START_TIME=$( echo "${MESSAGE_PAST}" | cut -d \| -f1 )
  if [[ ! ${START_TIME} =~ ${RE} ]]
  then
    START_TIME="${UNIX_TIME}"
  fi
  LAST_PING_TIME=$( echo "${MESSAGE_PAST}" | cut -d \| -f2 )
  if [[ ! ${LAST_PING_TIME} =~ ${RE} ]]
  then
    LAST_PING_TIME='0'
  fi
  MESSAGE_PAST=$( echo "${MESSAGE_PAST}" | cut -d \| -f3 )
  SECONDS_SINCE_PING="$( echo "${UNIX_TIME} - ${LAST_PING_TIME}" | bc -l )"

  # Send recovery message.
  if [[ -z "${MESSAGE_ERROR}" ]] && [[ -z "${MESSAGE_WARNING}" ]] && [[ ! -z "${MESSAGE_PAST}" ]] && [[ ! -z "${RECOVERED_MESSAGE_SUCCESS}" ]]
  then
    ERRORS=$( SEND_SUCCESS "${RECOVERED_MESSAGE_SUCCESS}" ":wrench: ${RECOVERED_TITLE_SUCCESS} :wrench:" )
    if [[ ! -z "${ERRORS}" ]]
    then
      echo "ERROR: ${ERRORS}"
    else
      SQL_QUERY "DELETE FROM system_log WHERE name == '${NAME}'; "
    fi
  fi

  # Send message out.
  ERRORS=''
  MESSAGE=''
  if [[ ! -z "${MESSAGE_ERROR}" ]] && [[ "${SECONDS_SINCE_PING}" -gt 300 ]]
  then
    ERRORS=$( SEND_ERROR "${MESSAGE_ERROR}" "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}" )
    MESSAGE="${MESSAGE_ERROR}"
  elif [[ ! -z "${MESSAGE_WARNING}" ]] && [[ "${SECONDS_SINCE_PING}" -gt 900 ]]
  then
    ERRORS=$( SEND_WARNING "${MESSAGE_WARNING}" "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}" )
    MESSAGE="${MESSAGE_WARNING}"
  elif [[ ! -z "${MESSAGE_INFO}" ]] && [[ "${SECONDS_SINCE_PING}" -gt 3600 ]]
  then
    ERRORS=$( SEND_INFO "${MESSAGE_INFO}" "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}" )
    MESSAGE="${MESSAGE_INFO}"
  elif [[ ! -z "${MESSAGE_SUCCESS}" ]]
  then
    ERRORS=$( SEND_SUCCESS "${MESSAGE_SUCCESS}" "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}" )
    MESSAGE="${MESSAGE_SUCCESS}"
  fi

  if [[ "${DEBUG_OUTPUT}" -eq 1 ]]
  then
    echo "system_log name ${NAME}"
    echo "Last ping: ${SECONDS_SINCE_PING}"
    if [[ ! -z "${MESSAGE_ERROR}" ]]
    then
      echo "Error: ${MESSAGE_ERROR}"
    fi
    if [[ ! -z "${MESSAGE_WARNING}" ]]
    then
      echo "Warning: ${MESSAGE_WARNING}"
    fi
    if [[ ! -z "${MESSAGE_INFO}" ]]
    then
      echo "Info: ${MESSAGE_INFO}"
    fi
    if [[ ! -z "${MESSAGE_SUCCESS}" ]]
    then
      echo "Success: ${MESSAGE_SUCCESS}"
    fi
    if [[ ! -z "${MESSAGE}" ]]
    then
      echo "Message: ${MESSAGE}"
    fi
    if [[ ! -z "${ERRORS}" ]]
    then
      echo "Errors: ${ERRORS}"
    fi
    echo
  fi

  # Write to the database.
  if [[ ! -z "${ERRORS}" ]]
  then
    echo "${ERRORS}" >/dev/tty
  elif [[ "${TEST_OUTPUT}" -eq 0 ]] && [[ ! -z "${MESSAGE}" ]]
  then
    SQL_QUERY "REPLACE INTO system_log (start_time,last_ping_time,name,message) VALUES ('${START_TIME}','${UNIX_TIME}','${NAME}','${MESSAGE}');"
  fi
}

 PROCESS_NODE_MESSAGES () {
  local ERRORS=''
  local MESSAGE=''
  local DATADIR=${1}
  local TYPE=${2}
  # 1=Error, 2=Warning, 3=Info, 4=Success, 5=Recovery
  local MESSAGE_TYPE=${3}
  local MESSAGE_TEXT=${4}
  local MESSAGE_TITLE=${5}
  local DISCORD_WEBHOOK_USERNAME=${6}
  local DISCORD_WEBHOOK_AVATAR=${7}

  # Get past events.
  UNIX_TIME=$( date -u +%s )
  MESSAGE_PAST=$( SQL_QUERY "SELECT start_time,last_ping_time,message FROM node_log WHERE conf_loc == '${DATADIR}' AND type == '${TYPE}'; " )
  START_TIME=$( echo "${MESSAGE_PAST}" | head -n1 | cut -d \| -f1 )
  if [[ ! ${START_TIME} =~ ${RE} ]]
  then
    START_TIME="${UNIX_TIME}"
  fi
  LAST_PING_TIME=$( echo "${MESSAGE_PAST}" | head -n1 | cut -d \| -f2 )
  if [[ ! ${LAST_PING_TIME} =~ ${RE} ]]
  then
    LAST_PING_TIME='0'
  fi
  MESSAGE_PAST=$( echo "${MESSAGE_PAST}" | cut -d \| -f3 )
  SECONDS_SINCE_PING="$( echo "${UNIX_TIME} - ${LAST_PING_TIME}" | bc -l )"

  # Send message out.
  ERRORS=''
  MESSAGE=''
  # Error Message.
  if [[ "${MESSAGE_TYPE}" -eq 1 ]] && [[ "${SECONDS_SINCE_PING}" -gt 300 ]]
  then
    ERRORS=$( SEND_ERROR "${MESSAGE_TEXT}" "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}" )
    MESSAGE="${MESSAGE_TEXT}"
  # Warning Message.
  elif [[ "${MESSAGE_TYPE}" -eq 2 ]] && [[ "${SECONDS_SINCE_PING}" -gt 900 ]]
  then
    ERRORS=$( SEND_WARNING "${MESSAGE_TEXT}" "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}" )
    MESSAGE="${MESSAGE_TEXT}"
  # Information Message.
  elif [[ "${MESSAGE_TYPE}" -eq 3 ]] && [[ "${SECONDS_SINCE_PING}" -gt 3600 ]]
  then
    ERRORS=$( SEND_INFO "${MESSAGE_TEXT}" "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}" )
    MESSAGE="${MESSAGE_TEXT}"
  # Success Message.
  elif [[ "${MESSAGE_TYPE}" -eq 4 ]] && [[ "${SECONDS_SINCE_PING}" -gt 7200 ]]
  then
    ERRORS=$( SEND_SUCCESS "${MESSAGE_TEXT}" "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}" )
    MESSAGE="${MESSAGE_TEXT}"
  # Send recovery message.
  elif [[ "${MESSAGE_TYPE}" -eq 5 ]] && [[ ! -z "${MESSAGE_PAST}" ]]
  then
    ERRORS=$( SEND_SUCCESS "${MESSAGE_TEXT}" ":wrench: ${MESSAGE_TEXT} :wrench:" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}" )
    if [[ -z "${ERRORS}" ]]
    then
      SQL_QUERY "DELETE FROM node_log WHERE conf_loc == '${DATADIR}' AND type == '${TYPE}'; "
    fi
  fi

  if [[ "${DEBUG_OUTPUT}" -eq 1 ]]
  then
    echo "node_log conf ${DATADIR} type ${TYPE}"
    echo "Last ping: ${SECONDS_SINCE_PING}"
    echo "Message Type: ${MESSAGE_TYPE}"
    echo "Message: ${MESSAGE_TEXT}"
    if [[ ! -z "${MESSAGE_TITLE}" ]]
    then
      echo "Message Title: ${MESSAGE_TITLE}"
    fi
    if [[ ! -z "${ERRORS}" ]]
    then
      echo "Errors: ${ERRORS}"
    fi
    echo
  fi

  # Write to the database.
  if [[ ! -z "${ERRORS}" ]]
  then
    echo "Error: ${ERRORS}"
  elif [[ "${TEST_OUTPUT}" -eq 0 ]] && [[ ! -z "${MESSAGE}" ]]
  then
    SQL_QUERY "REPLACE INTO node_log (start_time,last_ping_time,conf_loc,type,message) VALUES ('${START_TIME}','${UNIX_TIME}','${DATADIR}','${TYPE}','${MESSAGE}');"
  fi
}

 GET_LATEST_LOGINS () {
  if [[ "${DEBUG_OUTPUT}" -eq 1 ]]
  then
    echo 'Checking SSH logins'
  fi

  LAST_LOGIN_TIME_CHECK=$( SQL_QUERY "SELECT value FROM variables WHERE key == 'last_login_time_check' " )
  if [[ -z "${LAST_LOGIN_TIME_CHECK}" ]]
  then
    LAST_LOGIN_TIME_CHECK=0
  fi
  UNIX_TIME=$( date -u +%s )

  while read -r DATE_1 DATE_2 DATE_3 LINE
  do
    if [[ -z "${LINE}" ]]
    then
      continue
    fi

    UNIX_TIME_LOG=$( date -u --date="${DATE_1} ${DATE_2} ${DATE_3}" +%s )
    if [[ "${LAST_LOGIN_TIME_CHECK}" -gt "${UNIX_TIME_LOG}" ]]
    then
      continue
    fi

    LINE=$( echo "${LINE}" | sed 's/SHA[[:digit:]]\+.*$//' )
    SSH_USER=$( echo "${LINE}" | grep -Pio 'for .*? from' | cut -d ' ' -f 2 | sed 's/for //' | sed 's/ from//' )
    SSH_IP=$( echo "${LINE}" | grep -Pio 'from .*? port' | sed 's/from //' | sed 's/ port//' )

    VERB='in'
    if [[ $( echo "${LINE}" | grep -ci ': Accepted ' ) -eq 0 ]]
    then
      VERB='out'
    fi

    ERRORS=$( SEND_WARNING "${DATE_1} ${DATE_2} ${DATE_3} ${LINE}" ":unlock: User ${SSH_USER} logged ${VERB} at ${UNIX_TIME_LOG} from ${SSH_IP}" )
    if [[ ! -z "${ERRORS}" ]]
    then
      echo "ERROR: ${ERRORS}"
    elif [[ "${TEST_OUTPUT}" -eq 0 ]]
    then
      SQL_QUERY "REPLACE INTO variables (key,value) VALUES ('last_login_time_check','${UNIX_TIME}');"
    fi
  done <<< "$( grep 'port' /var/log/auth.log | grep -iv 'CRON\|preauth\|Invalid[[:space:]]user\|user[[:space:]]unknown\|major[[:space:]]versions[[:space:]]differ\|Failed[[:space:]]password\|authentication[[:space:]]failure\|refused[[:space:]]connect\|ignoring[[:space:]]max\|not[[:space:]]receive[[:space:]]identification\|[[:space:]]sudo\|[[:space:]]su\|Bad[[:space:]]protocol\|Disconnected[[:space:]]from[[:space:]]user\|Failed[[:space:]]none' )"
}

 CHECK_DISK () {
  NAME='disk_space'
  MESSAGE_ERROR=''
  MESSAGE_WARNING=''
  MESSAGE_INFO=''
  MESSAGE_SUCCESS=''

  FREEPSPACE_ALL=$( df -P . | tail -1 | awk '{print $4}' )
  FREEPSPACE_BOOT=$( df -P /boot | tail -1 | awk '{print $4}' )
  if [[ "${FREEPSPACE_ALL}" -lt "${LOW_HDD_ERROR_KB}" ]] || [[ "${TEST_OUTPUT}" -eq 1 ]]
  then
    FREEPSPACE_ALL=$( echo "${FREEPSPACE_ALL} / 1024" | bc )
    MESSAGE_ERROR="${MESSAGE_ERROR} Less than ${LOW_HDD_ERROR_MB} MB of free space is left on the drive. ${FREEPSPACE_ALL} MB left."
  fi
  if [[ "${FREEPSPACE_BOOT}" -lt "${LOW_HDD_BOOT_ERROR_KB}" ]] || [[ "${TEST_OUTPUT}" -eq 1 ]]
  then
    FREEPSPACE_BOOT=$( echo "${FREEPSPACE_BOOT} / 1024" | bc )
    MESSAGE_ERROR="${MESSAGE_ERROR} Less than ${LOW_HDD_BOOT_ERROR_MB} MB of free space is left in the boot folder. ${FREEPSPACE_BOOT} MB left."
  fi

  if [[ -z "${MESSAGE_ERROR}" ]]
  then
    if [[ "${FREEPSPACE_ALL}" -lt "${LOW_HDD_WARN_KB}" ]] || [[ "${TEST_OUTPUT}" -eq 1 ]]
    then
      FREEPSPACE_ALL=$( echo "${FREEPSPACE_ALL} / 1024" | bc )
      MESSAGE_WARNING="${MESSAGE_WARNING} Less than ${LOW_HDD_WARN_MB} MB of free space is left on the drive. ${FREEPSPACE_ALL} MB left."
    fi
    if [[ "${FREEPSPACE_BOOT}" -lt "${LOW_HDD_BOOT_WARN_KB}" ]] || [[ "${TEST_OUTPUT}" -eq 1 ]]
    then
      FREEPSPACE_BOOT=$( echo "${FREEPSPACE_BOOT} / 1024" | bc )
      MESSAGE_WARNING="${MESSAGE_WARNING} Less than ${LOW_HDD_BOOT_WARN_MB} MB of free space is left in the boot folder. ${FREEPSPACE_BOOT} MB left."
    fi
  fi

  if [[ ! -z "${MESSAGE_ERROR}" ]]
  then
    MESSAGE_ERROR=":floppy_disk: :fire: ${MESSAGE_ERROR} :fire: :floppy_disk:"
  fi
  if [[ ! -z "${MESSAGE_WARNING}" ]]
  then
    MESSAGE_WARNING=":floppy_disk: ${MESSAGE_WARNING} :floppy_disk:"
  fi

  if [[ "${DEBUG_OUTPUT}" -eq 1 ]]
  then
    echo "Freespace all: ${FREEPSPACE_ALL}"
    echo "Freespace boot: ${FREEPSPACE_BOOT}"
    echo
  fi

  RECOVERED_MESSAGE_SUCCESS="Hard drive has ${FREEPSPACE_ALL} MB Free; boot folder has ${FREEPSPACE_BOOT} MB Free."
  RECOVERED_TITLE_SUCCESS="Low diskspace issue has been resolved."
  PROCESS_MESSAGES "${NAME}" "${MESSAGE_ERROR}" "${MESSAGE_WARNING}" "${MESSAGE_INFO}" "${MESSAGE_SUCCESS}" "${RECOVERED_MESSAGE_SUCCESS}" "${RECOVERED_TITLE_SUCCESS}" "${DISCORD_WEBHOOK_USERNAME_DEFAULT}" "${DISCORD_WEBHOOK_AVATAR_DEFAULT}"
}

 CHECK_CPU_LOAD () {
  NAME='cpu_usage'
  MESSAGE_ERROR=''
  MESSAGE_WARNING=''
  MESSAGE_INFO=''
  MESSAGE_SUCCESS=''

  LOAD=$( uptime | grep -oE 'load average: [0-9]+([.][0-9]+)?' | grep -oE '[0-9]+([.][0-9]+)?' )
  CPU_COUNT=$( grep -c 'processor' /proc/cpuinfo )
  LOAD_PER_CPU="$( printf "%.3f\n" "$( bc -l <<< "${LOAD} / ${CPU_COUNT}" )" )"

  if [[ "$( echo "${LOAD_PER_CPU} >= ${CPU_LOAD_ERROR}" | bc -l )" -gt 0 ]] || [[ "${TEST_OUTPUT}" -eq 1 ]]
  then
    MESSAGE_ERROR=" :desktop: :fire:  CPU LOAD is over ${CPU_LOAD_ERROR}: ${LOAD_PER_CPU} :fire: :desktop: "
  elif [[ "$( echo "${LOAD_PER_CPU} > ${CPU_LOAD_WARN}" | bc -l )" -gt 0 ]] || [[ "${TEST_OUTPUT}" -eq 1 ]]
  then
    MESSAGE_WARNING=" :desktop: CPU LOAD is over ${CPU_LOAD_WARN}: ${LOAD_PER_CPU} :desktop: "
  fi

  if [[ "${DEBUG_OUTPUT}" -eq 1 ]]
  then
    echo "Load: ${LOAD}"
    echo "CPU Count: ${CPU_COUNT}"
    echo "Load per CPU: ${LOAD_PER_CPU}"
    echo
  fi

  RECOVERED_MESSAGE_SUCCESS="Load per CPU is ${LOAD_PER_CPU}."
  RECOVERED_TITLE_SUCCESS="CPU Load is back to normal."
  PROCESS_MESSAGES "${NAME}" "${MESSAGE_ERROR}" "${MESSAGE_WARNING}" "${MESSAGE_INFO}" "${MESSAGE_SUCCESS}" "${RECOVERED_MESSAGE_SUCCESS}" "${RECOVERED_TITLE_SUCCESS}" "${DISCORD_WEBHOOK_USERNAME_DEFAULT}" "${DISCORD_WEBHOOK_AVATAR_DEFAULT}"
}

 CHECK_SWAP () {
  NAME='swap_free'
  MESSAGE_ERROR=''
  MESSAGE_WARNING=''
  MESSAGE_INFO=''
  MESSAGE_SUCCESS=''

  SWAP_FREE_MB=$( free -wm | grep -i 'Swap:' | awk '{print $4}' )
  if [[ $( echo "${SWAP_FREE_MB} < ${LOW_SWAP_ERROR_MB}" | bc ) -gt 0 ]] || [[ "${TEST_OUTPUT}" -eq 1 ]]
  then
    MESSAGE_ERROR=":desktop: :fire: Swap is under ${LOW_SWAP_ERROR_MB} MB: ${SWAP_FREE_MB} MB :fire: :desktop: "
  fi
  if ([[ $( echo "${SWAP_FREE_MB} >= ${LOW_SWAP_ERROR_MB}" | bc ) -gt 0 ]] && [[ $( echo "${SWAP_FREE_MB} < ${LOW_SWAP_WARN_MB}" | bc ) -gt 0 ]]) || [[ "${TEST_OUTPUT}" -eq 1 ]]
  then
    MESSAGE_WARNING=":desktop: Swap is under ${LOW_SWAP_WARN_MB} MB: ${SWAP_FREE_MB} MB :desktop: "
  fi

  if [[ "${DEBUG_OUTPUT}" -eq 1 ]]
  then
    echo "Swap Free MB: ${SWAP_FREE_MB}"
    echo
  fi

  RECOVERED_MESSAGE_SUCCESS="Free Swap space is ${SWAP_FREE_MB} MB."
  RECOVERED_TITLE_SUCCESS="Free sawp space is back to normal."
  PROCESS_MESSAGES "${NAME}" "${MESSAGE_ERROR}" "${MESSAGE_WARNING}" "${MESSAGE_INFO}" "${MESSAGE_SUCCESS}" "${RECOVERED_MESSAGE_SUCCESS}" "${RECOVERED_TITLE_SUCCESS}" "${DISCORD_WEBHOOK_USERNAME_DEFAULT}" "${DISCORD_WEBHOOK_AVATAR_DEFAULT}"
}

 CHECK_RAM () {
  NAME='ram_free'
  MESSAGE_ERROR=''
  MESSAGE_WARNING=''
  MESSAGE_INFO=''
  MESSAGE_SUCCESS=''

  MEM_TOTAL=$( sudo cat /proc/meminfo | grep -i 'MemTotal:' | awk '{print $2}' | head -n 1 )
  MEM_AVAILABLE=$( sudo cat /proc/meminfo | grep -i 'MemAvailable:\|MemFree:' | awk '{print $2}' | tail -n 1 )
  MEM_AVAILABLE_MB=$( echo "${MEM_AVAILABLE} / 1024" | bc )
  PERCENT_FREE=$( echo "${MEM_AVAILABLE} / ${MEM_TOTAL}" | bc -l )
  PERCENT_FREE=$( echo "${PERCENT_FREE} * 100" | bc -l )

  if [[ "${TEST_OUTPUT}" -eq 1 ]] || ([[ $( echo "${PERCENT_FREE} < ${LOW_MEM_ERROR_PERCENT}" | bc -l ) -eq 1 ]] && [[ $( echo "${MEM_AVAILABLE_MB} < ${LOW_MEM_ERROR_MB}" | bc ) -gt 0 ]])
  then
    MESSAGE_ERROR=":desktop: :fire: Free RAM is under ${LOW_MEM_ERROR_MB} MB: ${MEM_AVAILABLE_MB} MB Percent Free: ${PERCENT_FREE}% :fire: :desktop: "
  elif [[ "${TEST_OUTPUT}" -eq 1 ]] || ([[ $( echo "${PERCENT_FREE} < ${LOW_MEM_WARN_PERCENT}" | bc -l ) -eq 1 ]] && [[ $( echo "${MEM_AVAILABLE_MB} < ${LOW_MEM_WARN_MB}" | bc ) -gt 0 ]])
  then
    MESSAGE_WARNING=":desktop: Free RAM is under ${LOW_MEM_WARN_MB} MB: ${MEM_AVAILABLE_MB} MB. Percent Free: ${PERCENT_FREE}% :desktop: "
  fi

  if [[ "${DEBUG_OUTPUT}" -eq 1 ]]
  then
    echo "Ram Free MB: ${MEM_AVAILABLE_MB}"
    echo "Percent Free: ${PERCENT_FREE}"
    echo
  fi

  RECOVERED_MESSAGE_SUCCESS="Free RAM is now at ${MEM_AVAILABLE_MB} MB."
  RECOVERED_TITLE_SUCCESS="Free RAM is back to normal."
  PROCESS_MESSAGES "${NAME}" "${MESSAGE_ERROR}" "${MESSAGE_WARNING}" "${MESSAGE_INFO}" "${MESSAGE_SUCCESS}" "${RECOVERED_MESSAGE_SUCCESS}" "${RECOVERED_TITLE_SUCCESS}" "${DISCORD_WEBHOOK_USERNAME_DEFAULT}" "${DISCORD_WEBHOOK_AVATAR_DEFAULT}"
}

 CHECK_OOM_KILLS () {
  LAST_OOM_TIME_CHECK=$( SQL_QUERY "SELECT value FROM variables WHERE key == 'last_oom_time_check' " )
  if [[ -z "${LAST_OOM_TIME_CHECK}" ]]
  then
    LAST_OOM_TIME_CHECK=0
  fi
  UNIX_TIME=$( date -u +%s )

  while read -r DATE_1 DATE_2 DATE_3 LINE
  do
    if [[ -z "${LINE}" ]]
    then
      continue
    fi

    UNIX_TIME_LOG=$( date -u --date="${DATE_1} ${DATE_2} ${DATE_3}" +%s )
    if [[ "${LAST_OOM_TIME_CHECK}" -gt "${UNIX_TIME_LOG}" ]]
    then
      continue
    fi

    ERRORS=$( SEND_ERROR "${DATE_1} ${DATE_2} ${DATE_3} ${LINE}" " :skull_crossbones: :fire: Process killed due to low memory :fire: :skull_crossbones: " )
    if [[ ! -z "${ERRORS}" ]]
    then
      echo "ERROR: ${ERRORS}"
    elif [[ "${TEST_OUTPUT}" -eq 0 ]]
    then
      SQL_QUERY "REPLACE INTO variables (key,value) VALUES ('last_oom_time_check','${UNIX_TIME}');"
    fi
  done <<< "$( grep -i 'out of memory' /var/log/kern.log )"
}

 CHECK_CLOCK () {
   # Get the last time this check was ran.
  CHECK_CLOCK_LAST_RUN=$( SQL_QUERY "SELECT value FROM variables WHERE key == 'system_clock_last_run' " )
  if [[ -z "${CHECK_CLOCK_LAST_RUN}" ]]
  then
    CHECK_CLOCK_LAST_RUN=0
  fi
  UNIX_TIME=$( date -u +%s )
  # Only run once every 30 min.
  CHECK_CLOCK_LAST_RUN=$(( CHECK_CLOCK_LAST_RUN + 1800 ))
  if [[ "${CHECK_CLOCK_LAST_RUN}" -gt "${UNIX_TIME}" ]]
  then
    if [[ "${DEBUG_OUTPUT}" -eq 1 ]]
    then
      echo "System clock check was already ran. ${CHECK_CLOCK_LAST_RUN} -gt ${UNIX_TIME}"
      echo
    fi
    return
  fi

  NAME='system_clock_check'
  MESSAGE_ERROR=''
  MESSAGE_WARNING=''
  MESSAGE_INFO=''
  MESSAGE_SUCCESS=''

  if [[ "${DEBUG_OUTPUT}" -eq 1 ]]
  then
    echo 'Checking system clock'
  fi

  TIME_OFFSET=$( ntpdate -q pool.ntp.org | tail -n 1 | grep -o 'offset.*' | awk '{print $2 }' | tr -d '-' )

  if [[ $( echo "${TIME_OFFSET} > 1" | bc ) -gt 0 ]] || [[ "${TEST_OUTPUT}" -eq 1 ]]
  then
    MESSAGE_ERROR=":watch: :fire: System Clock if off by over 1 second. Offset: ${TIME_OFFSET} seconds :fire: :watch: "
  fi
  if [[ $( echo "${TIME_OFFSET} > 0.1" | bc ) -gt 0 ]] || [[ "${TEST_OUTPUT}" -eq 1 ]]
  then
    MESSAGE_WARNING=":watch: System Clock if off by over 0.1 seconds. Offset: ${TIME_OFFSET} seconds :watch: "
  fi

  if [[ "${DEBUG_OUTPUT}" -eq 1 ]]
  then
    echo "System clock offset: ${TIME_OFFSET}"
    echo
  fi

  RECOVERED_MESSAGE_SUCCESS="System clock is now at ${TIME_OFFSET} seconds."
  RECOVERED_TITLE_SUCCESS="System clock is back to normal."
  PROCESS_MESSAGES "${NAME}" "${MESSAGE_ERROR}" "${MESSAGE_WARNING}" "${MESSAGE_INFO}" "${MESSAGE_SUCCESS}" "${RECOVERED_MESSAGE_SUCCESS}" "${RECOVERED_TITLE_SUCCESS}" "${DISCORD_WEBHOOK_USERNAME_DEFAULT}" "${DISCORD_WEBHOOK_AVATAR_DEFAULT}"
  SQL_QUERY "REPLACE INTO variables (key,value) VALUES ('system_clock_last_run','${UNIX_TIME}');"
}

 CHECK_DEBSUMS() {
  # Get the last time this check was ran.
  DEBSUMS_LAST_RUN=$( SQL_QUERY "SELECT value FROM variables WHERE key == 'debsums_last_run' " )
  if [[ -z "${DEBSUMS_LAST_RUN}" ]]
  then
    DEBSUMS_LAST_RUN=0
  fi
  UNIX_TIME=$( date -u +%s )
  # Only run once every 2 hours.
  DEBSUMS_LAST_RUN=$(( DEBSUMS_LAST_RUN + 7200 ))
  if [[ "${DEBSUMS_LAST_RUN}" -gt "${UNIX_TIME}" ]]
  then
    if [[ "${DEBUG_OUTPUT}" -eq 1 ]]
    then
      echo "Debsums was already ran. ${DEBSUMS_LAST_RUN} -gt ${UNIX_TIME}"
      echo
    fi
    return
  fi

  if [[ "${DEBUG_OUTPUT}" -eq 1 ]]
  then
    echo 'Running debsums'
  fi

  NAME='debsums_check'
  MESSAGE_ERROR=''
  MESSAGE_WARNING=''
  MESSAGE_INFO=''
  MESSAGE_SUCCESS=''

  RECOVERED_MESSAGE_SUCCESS="debsums doesn't show any errors."
  RECOVERED_TITLE_SUCCESS="debsums is good."

  DEBSUMS_OUTPUT=$( sudo debsums -c 2>&1 )
  # Debug Output
  if [[ "${DEBUG_OUTPUT}" -eq 1 ]]
  then
    echo "Timing: ${DEBSUMS_LAST_RUN} -gt ${UNIX_TIME}"
    echo "Debsums Output: ${DEBSUMS_OUTPUT}"
    echo
  fi

  if [[ ! -z "${DEBSUMS_OUTPUT}" ]]
  then
    BROKEN_PACKAGES=$( echo "${DEBSUMS_OUTPUT}" | grep -P -o '/.*?\s' | xargs dpkg -S | cut -d : -f 1  )
    OUTPUT=$( echo "${BROKEN_PACKAGES}" | xargs apt-get install --reinstall )
    DEBSUMS_OUTPUT=$( sudo debsums -c 2>&1 )
    if [[ ! -z "${DEBSUMS_OUTPUT}" ]]
    then
      MESSAGE_ERROR="There are still issues with the 'debsums -c' command:
${DEBSUMS_OUTPUT}"
    else
      MESSAGE_WARNING="The following packages were reinstalled:
${BROKEN_PACKAGES}"
    fi

    # Debug Output
    if [[ "${DEBUG_OUTPUT}" -eq 1 ]]
    then
      echo "NEW Debsums Output: ${DEBSUMS_OUTPUT}"
      echo "Broken Packages: ${BROKEN_PACKAGES}"
      echo "Reinstall Output: ${OUTPUT}"
      echo
    fi
  fi

  PROCESS_MESSAGES "${NAME}" "${MESSAGE_ERROR}" "${MESSAGE_WARNING}" "${MESSAGE_INFO}" "${MESSAGE_SUCCESS}" "${RECOVERED_MESSAGE_SUCCESS}" "${RECOVERED_TITLE_SUCCESS}" "${DISCORD_WEBHOOK_USERNAME_DEFAULT}" "${DISCORD_WEBHOOK_AVATAR_DEFAULT}"
  SQL_QUERY "REPLACE INTO variables (key,value) VALUES ('debsums_last_run','${UNIX_TIME}');"
}

 CHECK_RKHUNTER() {
  # Get the last time this check was ran.
  RKHUNTER_LAST_RUN=$( SQL_QUERY "SELECT value FROM variables WHERE key == 'rkhunter_last_run' " )
  if [[ -z "${RKHUNTER_LAST_RUN}" ]]
  then
    RKHUNTER_LAST_RUN=0
  fi
  UNIX_TIME=$( date -u +%s )
  # Only run once every 2 hours.
  RKHUNTER_LAST_RUN=$(( RKHUNTER_LAST_RUN + 7200 ))
  if [[ "${RKHUNTER_LAST_RUN}" -gt "${UNIX_TIME}" ]]
  then
    if [[ "${DEBUG_OUTPUT}" -eq 1 ]]
    then
      echo "RK Hunter was already ran. ${RKHUNTER_LAST_RUN} -gt ${UNIX_TIME}"
      echo
    fi
    return
  fi

  if [[ "${DEBUG_OUTPUT}" -eq 1 ]]
  then
    echo 'Running rkhunter'
  fi

  sudo rkhunter --propupd >/dev/null
  if [[ "${RKHUNTER_LAST_RUN}" -eq 0 ]] && [[ "$( sudo rkhunter -c --enable system_configs_ssh --rwo | grep -ic root )" -gt 0 ]]
  then
    echo 'RK Hunter adjusted for root login.'
    echo 'ALLOW_SSH_ROOT_USER=yes' | sudo tee -a /etc/rkhunter.conf >/dev/null
  fi
  sudo rkhunter -C >/dev/null

  NAME='rkhunter_check'
  MESSAGE_ERROR=''
  MESSAGE_WARNING=''
  MESSAGE_INFO=''
  MESSAGE_SUCCESS=''

  RECOVERED_MESSAGE_SUCCESS="rkhunter doesn't show any errors."
  RECOVERED_TITLE_SUCCESS="rkhunter is good."

  RKHUNTER_OUTPUT=$( sudo rkhunter -c --rwo 2>&1 )
  # Debug Output
  if [[ "${DEBUG_OUTPUT}" -eq 1 ]]
  then
    echo "Timing: ${RKHUNTER_LAST_RUN} -gt ${UNIX_TIME}"
    echo "RK Hunter Output: ${RKHUNTER_OUTPUT}"
    echo
  fi

  if [[ ! -z "${RKHUNTER_OUTPUT}" ]]
  then
    MESSAGE_ERROR="There are issues with the 'rkhunter -c --rwo' command:
${RKHUNTER_OUTPUT}"

  fi

  PROCESS_MESSAGES "${NAME}" "${MESSAGE_ERROR}" "${MESSAGE_WARNING}" "${MESSAGE_INFO}" "${MESSAGE_SUCCESS}" "${RECOVERED_MESSAGE_SUCCESS}" "${RECOVERED_TITLE_SUCCESS}" "${DISCORD_WEBHOOK_USERNAME_DEFAULT}" "${DISCORD_WEBHOOK_AVATAR_DEFAULT}"
  SQL_QUERY "REPLACE INTO variables (key,value) VALUES ('rkhunter_last_run','${UNIX_TIME}');"
}

 REPORT_INFO_ABOUT_NODE () {
  USRNAME=$( echo "${1}" | tr -d \" )
  DAEMON_BIN=$( echo "${2}" | tr -d \" )
  DATADIR=$( echo "${3}" | tr -d \" )
  MASTERNODE=$( echo "${4}" | tr -d \" )
  MNINFO=$( echo "${5}" | tr -d \" )
  GETBALANCE=$( echo "${6}" | tr -d \" )
  GETTOTALBALANCE=$( echo "${7}" | tr -d \" )
  STAKING=$( echo "${8}" | tr -d \" )
  GETCONNECTIONCOUNT=$( echo "${9}" | tr -d \" )
  GETBLOCKCOUNT=$( echo "${10}" | tr -d \" )
  UPTIME=$( echo "${11}" | tr -d \" )
  DAEMON_PID=$( echo "${12}" | tr -d \" )
  NETWORKHASHPS=$( echo "${13}" | tr -d \" )
  MNWIN=$( echo "${14}" | tr -d \" )
  VERSION=$( echo "${15}" | tr -d \" )

  if [[ -z "${USRNAME}" ]]
  then
    return
  fi

  if [[ ! ${MASTERNODE} =~ ${RE} ]]
  then
    return
  fi

  DISCORD_WEBHOOK_AVATAR=''
  DISCORD_WEBHOOK_USERNAME=''
  EXTRA_INFO=$( echo "${DAEMON_BIN_LUT}" | grep -E "^${DAEMON_BIN} " )
  if [[ ! -z "${EXTRA_INFO}" ]]
  then
    DISCORD_WEBHOOK_AVATAR=$( echo "${EXTRA_INFO}" | cut -d ' ' -f2 )
    DISCORD_WEBHOOK_USERNAME=$( echo "${EXTRA_INFO}" | cut -d ' ' -f3- )
  fi

  MIN_STAKE=0
  STAKE_REWARD=0
  MASTERNODE_REWARD=0
  NET_HASH_FACTOR=0
  TICKER_NAME='COIN'
  STAKE_REWARD_UPPER=0
  BLOCKTIME_SECONDS=60
  UPTIME_HUMAN=$( DISPLAYTIME "${UPTIME}" )

  EXTRA_INFO=$( echo "${DAEMON_BALANCE_LUT}" | grep -E "^${DAEMON_BIN} " )
  if [[ ! -z "${EXTRA_INFO}" ]]
  then
    MIN_STAKE=$( echo "${EXTRA_INFO}" | cut -d ' ' -f2 )
    STAKE_REWARD=$( echo "${EXTRA_INFO}" | cut -d ' ' -f3 )
    MASTERNODE_REWARD=$( echo "${EXTRA_INFO}" | cut -d ' ' -f4 )
    NET_HASH_FACTOR=$( echo "${EXTRA_INFO}" | cut -d ' ' -f7 )
    TICKER_NAME=$( echo "${EXTRA_INFO}" | cut -d ' ' -f8 )
    BLOCKTIME_SECONDS=$( echo "${EXTRA_INFO}" | cut -d ' ' -f9 )
    STAKE_REWARD_UPPER=$( echo "${STAKE_REWARD} + 0.3" | bc -l )
  fi

  # Report on connection count.
  if [[ ${GETCONNECTIONCOUNT} =~ ${RE} ]]
  then
    if [[ "${GETCONNECTIONCOUNT}" -lt 2 ]]
    then
      PROCESS_NODE_MESSAGES "${DATADIR}" "connection_count" "1" "__${USRNAME} ${DAEMON_BIN}__
  Connection Count (${GETCONNECTIONCOUNT}) is very low!" "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"
    elif [[ "${GETCONNECTIONCOUNT}" -lt 5 ]]
    then
      PROCESS_NODE_MESSAGES "${DATADIR}" "connection_count" "2" "__${USRNAME} ${DAEMON_BIN}__
  Connection Count (${GETCONNECTIONCOUNT}) is low!" "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"
    else
      PROCESS_NODE_MESSAGES "${DATADIR}" "connection_count" "5" "__${USRNAME} ${DAEMON_BIN}__
  Connection count has been restored (${GETCONNECTIONCOUNT})" "Connection Count Normal" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"
    fi
  fi

  # Report on masternode winner
  LASTCHKBLOCK=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'last_block_checked';" )
  if [[ -z ${LISTACCOUNTS} ]]
  then
      LISTACCOUNTS=$( $COMMAND} "personal.listAccounts" 2>/dev/null | jq -r '.[]' )
  fi
  
  
  # save miner in array
  CHKBLOCK=${LASTCHKBLOCK}
  while [[ $( echo "$CHKBLOCK < $CURRENTBLKNUM" | bc -l ) -eq 1 ]]
  do
    MINER[${CHKBLOCK}]=$( ${COMMAND} "nrg.getBlock($CHKBLOCK).miner" 2>/dev/null | jq -r '.' | tr '[:upper:]' '[:lower:]' )
    ((CHKBLOCK++))

  done
  
  # Get total balance in the wallet.
  GETTOTALBALANCE=0
  GETBALANCE=0
  ACCTBALANCE=0
  
  NRGUSDPRICE=''
  STARTMNBLK=''
  ENDMNBLK=''
  MNCOLLATERAL=''
  
  #MASTERNODE=0
  
  for ADDR in ${LISTACCOUNTS}
  do
    
    # Change address to lower case
    ADDR=$( echo ${ADDR} | tr '[:upper:]' '[:lower:]' )
    SHORTADDR=$( echo ${ADDR:2:6} )
    
    # Start from last checked block for ADDR
    CHKBLOCK=${LASTCHKBLOCK}
    
    # Get total staking account balance
    ACCTBALANCE=$( $COMMAND "web3.fromWei(nrg.getBalance('$ADDR'), 'energi')" 2>/dev/null )
    GETBALANCE=$( echo "$GETBALANCE + $ACCTBALANCE" | bc -l )
    
    # is a masternode?
    isADDRMN=$( ${COMMAND} "masternode.masternodeInfo('$ADDR').isAlive" 2>/dev/null )
    
    # If Masternode isAlive
    if [[ "${isADDRMN}" ]] && [[ ${MASTERNODE} -lt 2 ]]
    then
      MASTERNODE=2
      MNINFO=0
    elif [[ ! "${isADDRMN}"  ]] && [[ ${MASTERNODE} -lt 1 ]]
    then
      MASTERNODE=1
    fi 
       
    while [[ $( echo "$CHKBLOCK < $CURRENTBLKNUM" | bc -l ) -eq 1  ]]
    do
      BLOCKMINER=MINER[${CHKBLOCK}]

      # Update database if stake received
      if [[ ${ADDR} == ${BLOCKMINER} ]]
      then
        STAKERWD=Y
        REWARDTIME=$( ${COMMAND} "nrg.getBlock($CHKBLOCK).timestamp" 2>/dev/null )
        
        # Get price once
        if [[ -z "${NRGUSDPRICE}" ]]
        then
          NRGUSDPRICE=$( curl -H "Accept: application/json" --connect-timeout 30 -s "https://min-api.cryptocompare.com/data/price?fsym=NRG&tsyms=USD" | jq .USD )
        fi

        # No way to determine at the time. Assume default
        REWARDAMT=2.28
    
        SQL_QUERY "INSERT INTO stake_rewards (stakeAddress, rewardTime, blockNum, Reward, balance, nrgPrice) 
          VALUES ('${ADDR}','${REWARDTIME}','${CHKBLOCK}','${REWARDAMT}', '${ACCTBALANCE}', '${NRGUSDPRICE}');"
        
        if [[ ! -z ${RWDDATA} ]]
        then
          REWARDUTCTIME=$( date -d@$REWARDTIME +'%Y-%m-%d %H:%M:%S' )
          echo "${REWARDUTCTIME}, ${CHKBLOCK}, S, ${ADDR}, ${ACCTBALANCE}, ${REWARDAMT}, ${NRGUSDPRICE}" >> ${RWDDATA}
        fi
        log "${SHORTADDR}: *** Stake received ***"
          
        _PAYLOAD="
NRG Mkt Price: USD ${NRGUSDPRICE}
Account: ${SHORTADDR}
Stake Reward: ${REWARDAMT}"

        # Post message
        PROCESS_NODE_MESSAGES "${DATADIR}" "stake_reward" "4" "${_PAYLOAD}" "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"
        
        # Send EMAIL / SMS if set in ngrmon.conf
        if [[ "${SENDEMAIL}" = "Y" ]]
        then
          SEND_EMAIL "Stake received"
        fi
        if [[ "${SENDSMS}" = "Y" ]]
        then
          SEND_SMS "Stake received"
        fi 
      fi
    
      # If Address is an MN
      if [[ ${isADDRMN} ]] & [[ -z ${ENDMNBLK} ]]
      then

        if [[ -z ${MNCOLLATERAL} ]]
        then
          MNCOLLATERAL=$( $COMMAND "web3.fromWei(masternode.masternodeInfo('$ADDR').collateral, 'energi')" 2>/dev/null | jq -r '.' )
        fi
        
        MNCHKDONE=$( SQL_QUERY "SELECT mnBlocksReceived FROM mn_blocks WHERE mnAddress = '${ADDR}';" )
        if [[ ${MNCHKDONE} == N ]]
        then
          MNTOTALNRG=$( SQL_QUERY "SELECT mnTotalReward FROM mn_blocks WHERE mnAddress = '${ADDR}';" )
          STARTMNBLK=$( SQL_QUERY "SELECT startMnBlk FROM mn_blocks WHERE mnAddress = '${ADDR}';" )
          ENDMNBLK=$( SQL_QUERY "SELECT endMnBlk FROM mn_blocks WHERE mnAddress = '${ADDR}';" )
          if [[ ${ENDMNBLK} -eq 0 ]]
          then
            ENDMNBLK=''
          fi
        fi
        
        # Call txlistinternal API to get internal transactions
        TXLSTINT=$( curl -H "accept: application/json" -s "${NRGAPI}?module=account&action=txlistinternal&address=${ADDR}&startblock=${CHKBLOCK}&endblock=${CHKBLOCK}" )
        if [[ $(echo $TXLSTINT | jq -r '.message') == OK ]]
        then

          if [[ -z $STARTMNBLK ]]
          then
              STARTMNBLK=$CHKBLOCK
              MASTERNODE=2
              MNRWD=Y
          fi
          
          # Get price once
          if [[ -z "${NRGUSDPRICE}" ]]
          then
            NRGUSDPRICE=$( curl -H "Accept: application/json" --connect-timeout 30 -s "https://min-api.cryptocompare.com/data/price?fsym=NRG&tsyms=USD" | jq .USD )
          fi

          # Add rewards for block
          BLOCKSUMWEI=$( echo $TXLSTINT | jq -r '.result | map(.value | tonumber) | add ' )
          BLOCKSUMWEI=$( printf "%.0f" $BLOCKSUMWEI )
          BLOCKSUMNRG=$( echo " ${BLOCKSUMWEI} / 1000000000000000000 " | bc -l | sed '/\./ s/\.\{0,1\}0\{1,\}$//' )
          
          # Time of block generation
          REWARDTIME=$( ${COMMAND} "nrg.getBlock($CHKBLOCK).timestamp" 2>/dev/null )
       
          # Update database
          SQL_QUERY "INSERT INTO mn_rewards (mnAddress, rewardTime, blockNum, Reward, balance, nrgPrice)
            VALUES ('${ADDR}','${REWARDTIME}','${CHKBLOCK}','${BLOCKSUMNRG}', '${ACCTBALANCE}', '${NRGUSDPRICE}');"

          MNTOTALNRG=$( echo " ${MNTOTALNRG} + ${BLOCKSUMNRG} " | bc -l | sed '/\./ s/\.\{0,1\}0\{1,\}$//' )
    
        elif [[ ${isADDRMN} ]] && [[ ! -z $STARTMNBLK ]] && [[ $(echo $TXLSTINT | jq '.message' | awk '{print $2}' ) == internal ]] && [[ -z ${ENDMNBLK} ]]
        then
          # All consecutive masternode payout blocks were found
          ENDMNBLK=$CHKBLOCK
          if [[ ! -z $MNTOTALNRG ]]
          then
              SQL_QUERY "REPLACE INTO mn_blocks (mnAddress, mnBlocksReceived, startMnBlk, endMnBlk, mnTotalReward) 
                VALUES ('${ADDR}','Y', '${STARTMNBLK}', '${ENDMNBLK}', '${MNTOTALNRG}');" 
                
              if [[ ! -z ${RWDDATA} ]]
              then
                REWARDUTCTIME=$( date -d@$REWARDTIME +'%Y-%m-%d %H:%M:%S' )
                echo "${REWARDUTCTIME}, ${CHKBLOCK}, M, ${ADDR}, ${MNCOLLATERAL}, ${MNTOTALNRG}, ${NRGUSDPRICE}" >> ${RWDDATA}
              fi
              log "${SHORTADDR}: *** Stake received ***"
              
              # Get price once
              if [[ -z "${NRGUSDPRICE}" ]]
              then
                NRGUSDPRICE=$( curl -H "Accept: application/json" --connect-timeout 30 -s "https://min-api.cryptocompare.com/data/price?fsym=NRG&tsyms=USD" | jq .USD )
              fi
              
              _MNREWARDS=$( SQL_REPORT "SELECT blockNum,Reward FROM mn_rewards WHERE blockNum BETWEEN ${STARTMNBLK} and ${ENDMNBLK};" )
              
              _PAYLOAD="
              NRG Mkt Price: USD ${NRGUSDPRICE}
              Account: ${SHORTADDR}
              Masternode Collateral: ${MNCOLLATERAL} NRG
              Masternode reward: ${MNTOTALNRG} NRG
              ${_MNREWARDS}
              "
              
              # Post message
              PROCESS_NODE_MESSAGES "${DATADIR}" "mn_reward" "4" "${_PAYLOAD}" "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"
              
              # Send EMAIL / SMS if set in ngrmon.conf
              if [[ "${SENDEMAIL}" = "Y" ]]
              then
                SEND_EMAIL "Stake received"
              fi
              if [[ "${SENDSMS}" = "Y" ]]
              then
                SEND_SMS "Stake received"
              fi              
              
              # Reset after message processed
              #SQL_QUERY "UPDATE mn_blocks
              #  SET mnBlocksReceived = 'S',
              #      startMnBlk = '0',
              #      endMnBlk = '0'
              #  WHERE mnAddress = '${ADDR}';"
          fi
        fi
      fi 
      ((CHKBLOCK++))      
    done

    if [[ ${isADDRMN} ]] && [[ -z ${ENDMNBLK} ]]
    then
      # Not all consecutive blocks were found
      SQL_QUERY "REPLACE INTO mn_blocks (mnAddress, mnBlocksReceived, startMnBlk, endMnBlk, mnTotalReward) 
        VALUES ('${ADDR}', 'N', '${STARTMNBLK}', '0', '${MNTOTALNRG}');"
      
    fi
    
    if [[ ! ${STAKERWD} == Y ]] || [[ ! ${MNRWD} == Y  ]]
    then
       log "${SHORTADDR}: No stake reward"
    fi
    
  done
  
  # Check staking status.
  STAKING=0
  GETSTAKINGSTATUS="false"
  if [[ $( echo "${GETBALANCE} > 0" | bc -l ) -gt 0 ]]
  then
    GETSTAKINGSTATUS=$( ${COMMAND} "miner.stakingStatus().staking" 2>/dev/null )
    if [[ ${GETSTAKINGSTATUS} ]]
    then
      STAKING=1
    fi
  fi
  
  # Get total on node
  GETTOTALBALANCE=$( echo "$GETBALANCE + $MNCOLLATERAL" | bc -l )
  
  # Masternode Status.
  if [[ ${MASTERNODE} -eq 1 ]]
  then
    if [[ ${MNINFO} -eq 1 ]]
    then
      PROCESS_NODE_MESSAGES "${DATADIR}" "masternode_status" "3" "__${USRNAME} ${DAEMON_BIN}__
Masternode should be starting up soon." "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"
    elif [[ ${MNINFO} -eq 2 ]]
    then
      PROCESS_NODE_MESSAGES "${DATADIR}" "masternode_status" "2" "__${USRNAME} ${DAEMON_BIN}__
Masternode list shows the masternode as active bug masternode status doesn't. Hopefully this changes soon." "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"
    else
      PROCESS_NODE_MESSAGES "${DATADIR}" "masternode_status" "1" "__${USRNAME} ${DAEMON_BIN}__
Masternode is not currently running." "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"
    fi
  elif [[ ${MASTERNODE} -eq 2 ]]
  then
    if [[ ${MNINFO} -eq 2 ]]
    then
      PROCESS_NODE_MESSAGES "${DATADIR}" "masternode_status" "5" "__${USRNAME} ${DAEMON_BIN}__
Masternode status and masternode list are good!" "Masternode Running" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"
    elif [[ ${MNINFO} -eq 0 ]]
    then
      PROCESS_NODE_MESSAGES "${DATADIR}" "masternode_status" "5" "__${USRNAME} ${DAEMON_BIN}__
Masternode status is good!" "Masternode Running" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"
    fi
  fi

    
  # Update last_block_checked for next iteration
  SQL_QUERY "REPLACE INTO variables (key,value) VALUES ('last_block_checked','${CURRENTBLKNUM}');"

  # Report on uptime
  PAST_UPTIME=$( SQL_QUERY "SELECT value FROM variables WHERE key = '${DATADIR}:uptime';" )
  if [[ -z "${PAST_UPTIME}" ]]
  then
    PAST_UPTIME="${UPTIME}"
  fi
  echo "uptime: ${UPTIME}
past uptime: ${PAST_UPTIME}"
  if [[ "${UPTIME}" -lt "${PAST_UPTIME}" ]]
  then
    PAST_UPTIME_HUMAN=$( DISPLAYTIME "${PAST_UPTIME}" )

    if [[ "${PAST_UPTIME}" -lt 300 ]]
    then
      SEND_ERROR "__${USRNAME} ${DAEMON_BIN}__
Daemon was restarted mutiple times in the last 5 minutes.
Past uptime: ${PAST_UPTIME_HUMAN}
New uptime: ${UPTIME_HUMAN} " "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"
    else
      SEND_WARNING "__${USRNAME} ${DAEMON_BIN}__
Daemon was restarted.
Past uptime: ${PAST_UPTIME_HUMAN}
New uptime: ${UPTIME_HUMAN}" "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"
    fi
  fi
  SQL_QUERY "REPLACE INTO variables (key,value) VALUES ('${DATADIR}:uptime','${UPTIME}');"

  # Update & report on balance.
  PAST_BALANCE=$( SQL_QUERY "SELECT value FROM variables WHERE key = '${DATADIR}:balance';" )
  if [[ -z "${PAST_BALANCE}" ]]
  then
    PAST_BALANCE=0
    SQL_QUERY "REPLACE INTO variables (key,value) VALUES ('${DATADIR}:balance','${GETTOTALBALANCE}');"
  else
    SQL_QUERY "REPLACE INTO variables (key,value) VALUES ('${DATADIR}:balance','${GETTOTALBALANCE}');"
  fi
  BALANCE_DIFF=$( echo "${GETTOTALBALANCE} - ${PAST_BALANCE}" | bc -l )

  # Empty Wallet.
  if [[ $( echo "${BALANCE_DIFF} != 0 " | bc -l ) -eq 0 ]]
  then
    : # Do nothing.

  # Wallet has been drained.
  elif [[ -z "${GETTOTALBALANCE}" ]] || [[ $( echo "${GETTOTALBALANCE} < 0.1" | bc -l ) -eq 1 ]]
  then
    SEND_ERROR "__${USRNAME} ${DAEMON_BIN}__
Balance is now near zero ${TICKER_NAME}!
Before: ${PAST_BALANCE}
After: ${GETTOTALBALANCE} " "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"

  # Larger amount has been moved off this wallet.
  elif [[ $( echo "${BALANCE_DIFF} < -1" | bc -l ) -gt 0 ]]
  then
    SEND_WARNING "__${USRNAME} ${DAEMON_BIN}__
Balance has decreased by over 1 ${TICKER_NAME} Difference: ${BALANCE_DIFF}.
New Balance: ${GETTOTALBALANCE}" "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"

  # Small amount has been moved.
  elif [[ $( echo "${BALANCE_DIFF} < 1" | bc -l ) -gt 0 ]]
  then
    SEND_INFO "__${USRNAME} ${DAEMON_BIN}__
Small amout of ${TICKER_NAME} has been transfered Difference: ${BALANCE_DIFF}.
New Balance: ${GETTOTALBALANCE}" "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"

  # More than 1 Coin has been added.
  elif [[ $( echo "${BALANCE_DIFF} >= 1" | bc -l ) -gt 0 ]]
  then
    if [[ $( echo "${BALANCE_DIFF} == ${MASTERNODE_REWARD}" | bc -l ) -eq 1 ]]
    then
      SEND_SUCCESS "__${USRNAME} ${DAEMON_BIN}__
Masternode reward amout of ${BALANCE_DIFF} ${TICKER_NAME}.
New Balance: ${GETTOTALBALANCE}" "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"
    elif [[ $( echo "${BALANCE_DIFF} >= ${STAKE_REWARD}" | bc -l ) -gt 0 ]] && [[ $( echo "${BALANCE_DIFF} < ${STAKE_REWARD_UPPER}" | bc -l ) -gt 0 ]]
    then
      SEND_SUCCESS "__${USRNAME} ${DAEMON_BIN}__
Staking reward amout of ${BALANCE_DIFF} ${TICKER_NAME}.
New Balance: ${GETTOTALBALANCE}" "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"
    else
      SEND_SUCCESS "__${USRNAME} ${DAEMON_BIN}__
Larger amout of ${TICKER_NAME} has been transfered Difference: ${BALANCE_DIFF}.
New Balance: ${GETTOTALBALANCE}" "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"
    fi
  fi

  # Get average staking times for masternode and staking rewards.
 #   SECONDS_TO_AVERAGE_STAKE_MASTERNODE_REWARD=0
 #   SECONDS_TO_AVERAGE_STAKE_STAKING_REWARD=0
  COINS_STAKED_TOTAL_NETWORK=$( echo "${NETWORKHASHPS} * ${NET_HASH_FACTOR}" | bc -l )
 #   if [[ ! -z "${COINS_STAKED_TOTAL_NETWORK}" ]] && [[ $( echo "${COINS_STAKED_TOTAL_NETWORK} != 0" | bc -l ) -eq 1 ]]
 #   then
 #     SECONDS_TO_AVERAGE_STAKE_MASTERNODE_REWARD=$( echo "${MASTERNODE_REWARD} / ${GETBALANCE} * ${BLOCKTIME_SECONDS}" | bc -l )
 #     SECONDS_TO_AVERAGE_STAKE_STAKING_REWARD=$( echo "${STAKE_REWARD} / ${GETBALANCE} * ${BLOCKTIME_SECONDS}" | bc -l )
 #   fi
  # Report on staking.
  TIME_TO_STAKE=''
  if [[ ! -z "${GETBALANCE}" ]] && [[ "$( echo "${GETBALANCE} > 0.0" | bc -l )" -gt 0 ]]
  then

    if [[ ! -z "${COINS_STAKED_TOTAL_NETWORK}" ]] && [[ $( echo "${COINS_STAKED_TOTAL_NETWORK} != 0" | bc -l ) -eq 1 ]]
    then

      # Better staking info
      if [[ ! -z "${ALL_STAKE_INPUTS_BALANCE_COUNT}" ]]
      then
        STAKE_GETBALANCE=$( echo "${ALL_STAKE_INPUTS_BALANCE_COUNT}" | awk '{print $1}' )
        SECONDS_TO_AVERAGE_STAKE=$( echo "${COINS_STAKED_TOTAL_NETWORK} / ${STAKE_GETBALANCE} * ${BLOCKTIME_SECONDS}" | bc -l )
      else
        SECONDS_TO_AVERAGE_STAKE=$( echo "${COINS_STAKED_TOTAL_NETWORK} / ${GETBALANCE} * ${BLOCKTIME_SECONDS}" | bc -l )
      fi
      TIME_TO_STAKE=$( DISPLAYTIME "${SECONDS_TO_AVERAGE_STAKE}" )
    fi

    if [[ "$( echo "${MIN_STAKE} > ${GETBALANCE}" | bc -l )" -gt 0 ]]
    then
      PROCESS_NODE_MESSAGES "${DATADIR}" "staking_balance" "2" "__${USRNAME} ${DAEMON_BIN}__
Balance (${GETBALANCE}) is below the minimum staking threshold (${MIN_STAKE}).
${GETBALANCE} < ${MIN_STAKE} " "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"
    else
      PROCESS_NODE_MESSAGES "${DATADIR}" "staking_balance" "5" "__${USRNAME} ${DAEMON_BIN}__
Has enough coins to stake now!" "Balance is above the minimum" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"
      if [[ "${STAKING}" -eq 0 ]]
      then
        GETSTAKINGSTATUS=$( su "${USRNAME}" -c "\"${COMMAND}\" miner.stakingStatus().staking\" 2>/dev/null" )
        PROCESS_NODE_MESSAGES "${DATADIR}" "staking_status" "2" "__${USRNAME} ${DAEMON_BIN}__
${GETSTAKINGSTATUS}" "" "" "" "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"
      fi
      if [[ "${STAKING}" -eq 1 ]]
      then
        PROCESS_NODE_MESSAGES "${DATADIR}" "staking_status" "5" "__${USRNAME} ${DAEMON_BIN}__
Staking status is now TRUE!" "Staking is enabled" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"
      fi
    fi
  fi

  # Report on chain splits
#      SEND_WARNING "__${USRNAME} ${DAEMON_BIN}__
#Chain Split detected.
#Current height: ${GETBLOCKCOUNT}
#Split Height: ${SPLIT_HEIGHT}
#Split Branch Lenght: ${SPLIT_BRANCHLEN}
#Split Hash: ${SPLIT_HASH}" ":warning: Warning Chain :link: Split :warning:" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"
#
#      SQL_QUERY "REPLACE INTO variables (key,value) VALUES ('${DATADIR}:chain_split','${SPLIT_HEIGHT}');"
#    fi
# fi

  # Report on daemon info.
  STAKING_TEXT='Disabled'
  if [[ "${STAKING}" -eq 1 ]]
  then
    STAKING_TEXT='Enabled'
  fi
  MASTERNODE_TEXT='Disabled'
  if [[ ${MASTERNODE} -eq 2 ]]
  then
    MASTERNODE_TEXT='Enabled but not enabled in masternode list'
    if [[ ${MNINFO} -eq 2 ]]
    then
      MASTERNODE_TEXT='Enabled'
    fi
  fi

  _PAYLOAD="__${USRNAME} ${DAEMON_BIN} ${DATADIR}__
BlockCount: ${GETBLOCKCOUNT}
Connections: ${GETCONNECTIONCOUNT}
Staking Status: ${STAKING_TEXT}
Masternode Status: ${MASTERNODE_TEXT}
PID: ${DAEMON_PID}
Uptime: ${UPTIME} seconds (${UPTIME_HUMAN})"

#  if [[ ! -z "${GETBALANCE}" ]] && [[ "$( echo "${GETBALANCE} > 0.0" | bc -l )" -gt 0 ]]
#  then
#    _PAYLOAD="${_PAYLOAD}
#Balance: ${GETBALANCE}
#Total Balance: ${GETTOTALBALANCE}"
#  fi
#  if [[ ! -z "${TIME_TO_STAKE}" ]]
#  then
#    _PAYLOAD="${_PAYLOAD}
#Staking Average ETA: ${TIME_TO_STAKE}"
#  fi

  PROCESS_NODE_MESSAGES "${DATADIR}" "node_info" "3" "${_PAYLOAD}" "" "${DISCORD_WEBHOOK_USERNAME}" "${DISCORD_WEBHOOK_AVATAR}"
}

 GET_INFO_ON_THIS_NODE () {
  USRNAME=${1}
  BIN_LOC=${2}
  DAEMON_BIN=${3}
  DATADIR=${4}
  DAEMON_PID=${5}
  UPTIME=${6}

  # GETBALANCE=0
  # GETTOTALBALANCE=0
  # is the daemon running.
  if [[ -z "${DAEMON_PID}" ]]
  then
    REPORT_INFO_ABOUT_NODE "${USRNAME}" "${DAEMON_BIN}" "${DATADIR}" "-1" "This node is not running."
    return
  fi

  # setup vars.
  GETBLOCKCOUNT=$( ${COMMAND} "nrg.blockNumber" 2>/dev/null | jq -r '.' )
  GETCONNECTIONCOUNT=$( ${COMMAND} "net.peerCount" 2>/dev/null | jq -r '.' )
  
  if [[ -z ${DATADIR} ]]
  then
    DATADIR=$( ps -ef | grep datadir | grep -v "grep datadir" | grep -v "color" )
    DATADIR=$( echo $DATADIR | awk -F'datadir' '{print $2}' | awk -F' ' '{print $1}' )
  fi

  if [[ -z "${GETBLOCKCOUNT}" ]] && [[ -z "${GETCONNECTIONCOUNT}" ]]
  then
    REPORT_INFO_ABOUT_NODE "${USRNAME}" "${DAEMON_BIN}" "${DATADIR}" "-2" "This node is frozen. PID: ${DAEMON_PID}"
    return
  fi

  # Get the version number.
  VERSION=$( "energi3" version  2>/dev/null | grep \"^Version:\" | sed 's/[^0-9.]*\([0-9.]*\).*/\1/' )
  if [[ -z "${VERSION}" ]]
  then
    VERSION=$( ${COMMAND} "admin.nodeInfo.name" 2>/dev/null | awk -F\/ '{print $2}' | sed 's/[^0-9.]*\([0-9.]*\).*/\1/' )
  fi

  if [[ -z ${LISTACCOUNTS} ]]
  then
      LISTACCOUNTS=$( ${COMMAND} "personal.listAccounts" 2>/dev/null | jq -r '.[]' )
  fi
  
  ALL_STAKE_INPUTS_BALANCE_COUNT=''
  if [[ $( echo "${GETBALANCE} > 0" | bc -l ) -gt 0 ]]
  then
      NUMBER_OF_ACCOUNTS=$( echo "${LISTACCOUNTS}" | wc -w )
      ALL_STAKE_INPUTS_BALANCE_COUNT="${STAKE_INPUTS_BALANCE} ${NUMBER_OF_ACCOUNTS}"
  fi

  # Check networkhashps
  GETNETHASHRATE=$( su "${USRNAME}" -c "\"${COMMAND}\" \" miner.getHashrate()" 2>/dev/null | grep -Eo '[+-]?[0-9]+([.][0-9]+)?' 2>/dev/null )
  if [[ -z "${GETNETHASHRATE}" ]]
  then
    GETNETHASHRATE=0
  fi
  
  if [[ -z ${MASTERNODE} ]]
  then
     MASTERNODE=0
  fi
  
  if [[ -z ${MNINFO} ]]
  then
     MNINFO=0
  fi

  # Output info.
  REPORT_INFO_ABOUT_NODE "${USRNAME}" "${DAEMON_BIN}" "${DATADIR}" "${MASTERNODE}" "${MNINFO}" "${GETBALANCE}" "${GETTOTALBALANCE}" "${STAKING}" "${GETCONNECTIONCOUNT}" "${GETBLOCKCOUNT}" "${UPTIME}" "${DAEMON_PID}" "${GETNETHASHRATE}" "${MNWIN}" "${VERSION}"
}

 GET_NODE_INFO () {
   DAEMON_BIN_FILTER="${1}"

  FILENAME_WITH_FUNCTIONS=''
  if [[ -r /var/multi-masternode-data/.bashrc ]]
  then
    FILENAME_WITH_FUNCTIONS='/var/multi-masternode-data/.bashrc'
  elif [[ -r /root/.bashrc ]]
  then
    FILENAME_WITH_FUNCTIONS='/root/.bashrc'
  elif [[ -r /home/ubuntu/.bashrc ]]
  then
    FILENAME_WITH_FUNCTIONS='/home/ubuntu/.bashrc'
  fi

  LSLOCKS=$( lslocks -n -o COMMAND,PID,PATH | grep -v ' /run/' )
  PS_LIST=$( ps --no-headers -axo user:32,pid,etimes,command )

  USR_HOME_DIR=$( grep nrgstaker /etc/passwd | awk -F: '{print $6}' )
  if [[ "${USR_HOME_DIR}" == 'X' ]]
  then
    USR_HOME_DIR=${USR_HOME_DIR_ALT}
  fi

  if [[ "${#USR_HOME_DIR}" -lt 3 ]] || [[ ${USR_HOME_DIR} == /var/* ]] || [[ ${USR_HOME_DIR} == '/proc' ]] || [[ ${USR_HOME_DIR} == '/dev' ]] || [[ ${USR_HOME_DIR} == /run/* ]] || [[ ${USR_HOME_DIR} == '/nonexistent' ]]
  then
    continue
  fi

  if [[ ! -d "${USR_HOME_DIR}" ]]
  then
    continue
  fi

  MN_USRNAME=$( basename "${USR_HOME_DIR}" )

  DAEMON_BIN=''
  CONTROLLER_BIN=''

  CONF_LOCATIONS=$( find "${USR_HOME_DIR}" -name "nodekey" 2>/dev/null | grep -v "Permission denied" )
  if [[ -z "${CONF_LOCATIONS}" ]]
  then
    continue
  fi
  CONF_FOLDER=$( dirname "${CONF_LOCATIONS}" )
  CONF_LOCATIONS=$( grep --include=\*.rpl -rl "rpc" "${CONF_FOLDER}" )

  if [[ -z "${CONF_LOCATIONS}" ]] && [[ "$( grep -c "energi3 \"${MN_USRNAME}\"" "${FILENAME_WITH_FUNCTIONS}" )" -gt 0 ]]
  then
    CONF_LOCATIONS=$( "${MN_USRNAME}" rpl )
  fi

  while read -r CONF_LOCATION
  do
    FUNCTION_PARAMS=''
    DAEMON_BIN_LOC=''
    CONTROLLER_BIN_LOC=''
    if [[ $( grep -ric "nomnmon" "${CONF_LOCATION}" ) -gt 0 ]]
    then
      continue
    fi

    # Get daemon bin name and pid from lock in toml folder.
    CONF_FOLDER=$( dirname "${CONF_LOCATION}" )
    DAEMON_BIN=$( echo "${LSLOCKS}" | grep -m 1 "${CONF_FOLDER}" | awk '{print $1}' )
    CONTROLLER_BIN="${DAEMON_BIN}"
    DAEMON_PID=$( echo "${LSLOCKS}" | grep -m 1 "${CONF_FOLDER}" | awk '{print $2}' )

    # Get path to daemon bin.
    if [[ ! -z "${DAEMON_PID}" ]]
    then
      DAEMON_BIN_LOC=$( echo "${PS_LIST}" | cut -c 32- | grep " ${DAEMON_PID} " | awk '{print $3}' )
      CONTROLLER_BIN_LOC="${DAEMON_BIN_LOC}"
      COMMAND_FOLDER=$( dirname "${DAEMON_BIN_LOC}" )
      CONTROLLER_BIN_FOLDER=$( find "${COMMAND_FOLDER}" -executable -type f 2>/dev/null | grep -Ei "${DAEMON_BIN}$" )
      if [[ ! -z "${CONTROLLER_BIN_FOLDER}" ]]
      then
        CONTROLLER_BIN_LOC="${CONTROLLER_BIN_FOLDER}"
      fi
    fi

    UPTIME=0
    if [[ ! -z "${DAEMON_PID}" ]]
    then
      UPTIME=$( echo "${PS_LIST}" | cut -c 32- | grep " ${DAEMON_PID} " | awk '{print $2}' | head -n 1 | awk '{print $1}' | grep -o '[0-9].*' )
    fi

    # Skip if filtered out
    if [[ ! -z "${DAEMON_BIN_FILTER}" ]] && [[ "${DAEMON_BIN_FILTER}" != "${DAEMON_BIN}" ]]
    then
      continue
    fi

    if [[ "${DEBUG_OUTPUT}" -eq 1 ]]
    then
      echo
      echo "+++++++++++++++++++++++++++++"
      echo "Username: ${USRNAME} ${MN_USRNAME}"
      echo "Cli: ${CONTROLLER_BIN} ${CONTROLLER_BIN_LOC}"
      echo "Daemon: ${DAEMON_BIN} ${DAEMON_BIN_LOC}"
      echo "Conf Location: ${CONF_LOCATION}"
      echo "PID: ${DAEMON_PID}"
      echo "Uptime: ${UPTIME}"
      echo
    fi

    # Skip if the controller bin or configuration is not a file.
    if [[ ! -f "${CONTROLLER_BIN_LOC}" ]] || [[ ! -f "${CONF_LOCATION}" ]]
    then
      if [[ "${DEBUG_OUTPUT}" -eq 1 ]]
      then
        echo "${CONTROLLER_BIN_LOC} or ${CONF_LOCATION} is not a file."
        echo
      fi
      #continue
    fi

    GET_INFO_ON_THIS_NODE "${USRNAME}" "${CONTROLLER_BIN_LOC}" "${DAEMON_BIN}" "${CONF_LOCATION}" "${DAEMON_PID}" "${UPTIME}"
  done <<< "${CONF_LOCATIONS}"

 
}

 NOT_CRON_WORKFLOW () {

  if [[ -z ${DAEMON_BIN} ]]
  then
    DAEMON_BIN="energi3"
  fi

  echo
  echo -e "\e[4mInteractive Section. Press enter to use defaults.\e[0m"
  SERVER_ALIAS=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'server_alias';" )
  if [[ -z "${SERVER_ALIAS}" ]]
  then
    SERVER_ALIAS=$( hostname )
  fi
  printf "Current alias for this server: \e[3m"
  read -e -i "${SERVER_ALIAS}" -r
  printf "\e[0m"
  SQL_QUERY "REPLACE INTO variables (key,value) VALUES ('server_alias','${REPLY}');"

  echo
  echo -ne "IP Address: "; hostname -i
  SHOW_IP=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'show_ip';" )
  if [[ -z "${SHOW_IP}" ]] || [[ "${SHOW_IP}" == '1' ]]
  then
    SHOW_IP='y'
  else
    SHOW_IP='n'
  fi
  printf "Display IP in logs (y/n)? \e[3m"
  read -e -i "${SHOW_IP}" -r
  printf "\e[0m"
  REPLY=${REPLY,,} # tolower
  if [[ "${REPLY}" == y ]]
  then
    SQL_QUERY "REPLACE INTO variables (key,value) VALUES ('show_ip','1');"
  else
    SQL_QUERY "REPLACE INTO variables (key,value) VALUES ('show_ip','0');"
  fi

  echo
  PREFIX='Setup'
  REPLY='y'
  DISCORD_WEBHOOK_URL=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'discord_webhook_url_error';" )
  if [[ ! -z "${DISCORD_WEBHOOK_URL}" ]]
  then
    REPLY='n'
    PREFIX='Redo'
  fi
  echo -en "${PREFIX} Discord Bot webhook URLs (y/n)? \e[3m"
  read -e -i "${REPLY}" -r
  printf "\e[0m"
  REPLY=${REPLY,,} # tolower
  if [[ "${REPLY}" == y ]]
  then
    GET_DISCORD_WEBHOOKS
    echo "Discord Done"
  fi

  echo
  PREFIX='Setup'
  REPLY='y'
  DISCORD_WEBHOOK_URL=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'discord_webhook_url_error';" )
  CHAT_ID=$( SQL_QUERY "SELECT value FROM variables WHERE key = 'telegram_chatid';" )
  if [[ ! -z "${DISCORD_WEBHOOK_URL}" ]]
  then
    REPLY='n'
  fi
  if [[ ! -z "${CHAT_ID}" ]]
  then
    REPLY='n'
    PREFIX='Redo'
  fi
  echo -en "\e[3m${PREFIX} Telegram Bot token (y/n)?\e[0m "
  read -e -i "${REPLY}" -r
  printf "\e[0m"
  REPLY=${REPLY,,} # tolower
  if [[ "${REPLY}" == y ]]
  then
    TELEGRAM_SETUP
    echo "Telegram Done"
  fi

  echo
  echo "Installing as a systemd service."
  sleep 1
  INSTALL_NRGMON_SERVICE
  echo "Service Install Done"
  return 1 2>/dev/null || exit 1
}

 # Main
  if [[ "${arg1}" == 'node_run' ]]
  then
    GET_NODE_INFO "${arg2}" "${arg3}"
  elif [[ "${arg1}" != 'cron' ]]
  then
    NOT_CRON_WORKFLOW
  else
    GET_LATEST_LOGINS
    CHECK_DISK
    CHECK_CPU_LOAD
    CHECK_SWAP
    CHECK_RAM
    CHECK_OOM_KILLS
    CHECK_CLOCK
    CHECK_DEBSUMS
    CHECK_RKHUNTER
    GET_NODE_INFO
  fi

 # End of the masternode monitor script.