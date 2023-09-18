#!/bin/bash

usage() {
  cat <<EOF
USAGE
  bash $0 [OPTIONS]

  This script removes orphaned Icinga time series data from InfluxDB by:
    - discovering which hosts are currently being monitored by icinga
    - discovering what metrics ("measurements") Icinga has stored in the influx db
    - reviewing each metric for entries regarding hosts that are NOT monitored by icinga
    - deleting the measurement entries for those hosts from the influx db

OPTIONS
  -u <value>  Icinga2 API username (REQUIRED)
  -p <value>  Icinga2 API password (REQUIRED)
  -d <value>  Influx DB name (REQUIRED)
  -u <value>  Icinga2 API URL (REQUIRED)
  -h          Displays this help message

EXAMPLES
  bash $0 -u encompaas_api_user -p <password> -d "icinga2" -u "https://<myhost>:5665"

EOF
  exit 3 # <-- make sure the script exits with an error code if no params are given.
}

# Set the default value of boolean timeout_ignore
timeout_ignore=false

while getopts ":u:p:h:" option; do
  case "${option}" in
  u) ICINGA2_API_USERNAME=${OPTARG} ;;
  p) ICINGA2_API_PASSWORD=${OPTARG} ;;
  d) INFLUX_DATABASE=${OPTARG} ;;
  u) ICINGA2_API_URL=${OPTARG} ;;
  h) ;;
  *) ;; # Default behaviour
  esac
done

if [[ "$timeout_ignore" != true ]] && [[ "$timeout_ignore" != false ]]; then
  echo "timeout_ignore Not a boolean value."
  usage
fi

# Validate that all values are set (all CAPS are environment variables as established on Ansible container)
if [[
  -z $ICINGA2_API_USERNAME ||
  -z $ICINGA2_API_PASSWORD ||
  -z $INFLUX_DATABASE ||
  -z $ICINGA2_API_URL ]]; then
  usage
fi

green=$(tput setaf 2)    # sets the foreground color to green
grey=$(tput setaf 241)   # sets the foreground color to grey
red=$(tput setaf 196)    # sets the foreground color to red
yellow=$(tput setaf 220) # sets the foreground color to yellow
no_colour=$(tput sgr0)   # No Color

write_comment() {
  echo ${green}-- ${1}${no_colour}
}

write_warning() {
  echo ${yellow}-- ${1}${no_colour}
}

write_skip() {
  echo ${grey}-- ${1}${no_colour}
}

write_error() {
  echo ${red}${1}${no_colour}
}

# Reset position of first non-option argument
shift "$((OPTIND - 1))"

# Global variables
SECONDS=0

# Disable SSL certificate validation
export PYTHONWARNINGS="ignore:Unverified HTTPS request"

write_comment "Getting hostnames from Icinga2"

icinga2_hostnames_headers='-H "Accept: application/json"'
icinga2_hostnames_data='{"attrs": ["name"]}'
icinga2_hostnames_response=$(curl -X GET -s $icinga2_hostnames_headers -u $ICINGA2_API_USERNAME:$ICINGA2_API_PASSWORD -d "$icinga2_hostnames_data" --insecure "$ICINGA2_API_URL/v1/objects/hosts")
icinga2_hostnames_json=$(echo $icinga2_hostnames_response | jq '.results')
icinga2_hostnames=()

for hostname in $(echo $icinga2_hostnames_json | jq -r '.[].name'); do
    icinga2_hostnames+=("$hostname")
done

write_comment "Icinga2 returned ${#icinga2_hostnames[@]} hosts."

write_comment "Getting measurement list from InfluxDB"

db_list_measurements_command=("influx" "-database" "$INFLUX_DATABASE" "-execute" "SHOW MEASUREMENTS" "-format" "json")
db_list_measurements_result=$( "${db_list_measurements_command[@]}" )
db_measurements_json=$(echo "$db_list_measurements_result" | jq -r '.results[0].series[0].values[] | .[]')
db_measurements=()

while IFS= read -r measurement; do
    db_measurements+=("$measurement")
done <<< "$db_measurements_json"

write_comment "InfluxDB returned ${#db_measurements[@]} measurements."

for measurement in "${db_measurements[@]}"; do
    write_comment "Cleaning up measurement $measurement"
    # Get hostnames in measurement
    measurement_list_hostnames_command=("influx" "-database" "$INFLUX_DATABASE" "-execute" "SHOW TAG VALUES FROM \"$measurement\" WITH KEY = \"hostname\"" "-format" "json")
    measurement_list_hostnames_result=$( "${measurement_list_hostnames_command[@]}" )
    measurement_hostnames_json=$(echo $measurement_list_hostnames_result | jq '.results[0]')

    if [ ! -z "$(echo $measurement_hostnames_json | jq -r '.series')" ]; then
        measurement_hostnames_json_series=$(echo "$measurement_hostnames_json" | jq -r '.series[0].values[] | .[1]')
        measurement_hostnames=()
        measurement_orphaned_hosts=()

        while IFS= read -r hostname; do
            measurement_hostnames+=("$hostname")

            if [[ ! " ${icinga2_hostnames[@]} " =~ " $hostname " ]]; then
                write_comment "Hostname $hostname does not exist in Icinga2!"

                measurement_orphaned_hosts+=("$hostname")

                write_comment "Dropping all series for host $hostname"

                drop_series_command=("influx" "-database" "$INFLUX_DATABASE" "-execute" "DROP SERIES WHERE \"hostname\" = '$hostname'")
                drop_series_result=$( "${drop_series_command[@]}" )
                # Uncomment the line below to print output of DROP SERIES command, which is usually empty
                #echo "DROP SERIES returned: $drop_series_result"
            fi
        done <<< "$measurement_hostnames_json_series"

        write_comment "Measurement $measurement returned ${#measurement_orphaned_hosts[@]}/${#measurement_hostnames[@]} orphaned/total hosts."
    else
        write_comment "No hostnames in measurement $measurement."
    fi
done

write_comment "Time taken (HH:MM:SS): $(date -d@$SECONDS -u +%H:%M:%S)"
