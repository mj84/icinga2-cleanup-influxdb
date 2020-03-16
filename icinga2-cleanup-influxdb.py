#!/usr/bin/env python3
import argparse
import json
import subprocess
import requests
# Disable SSL certificate validation
from requests.packages.urllib3.exceptions import InsecureRequestWarning
requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

INFLUX_DATABASE = 'icinga2'
ICINGA2_API_URL = 'https://1.2.3.4:5665'
ICINGA2_API_USERNAME = 'icinga2-api-user'
ICINGA2_API_PASSWORD = 'password'

if __name__ == "__main__":
  parser = argparse.ArgumentParser()
  parser.add_argument('-d', '--dryrun', action='store_true',
                      help='show what would be dropped')
  args = parser.parse_args()

# Read hostnames from Icinga2
print('''+------------------------------------------------------------------+
Getting hostnames from Icinga2''')
icinga2_hostnames_headers = {'X-HTTP-Method-Override': 'GET'}
icinga2_hostnames_data = { 'attrs': ['name'] }
icinga2_hostnames_request = requests.post('%s/v1/objects/hosts' % ICINGA2_API_URL,
    auth=(ICINGA2_API_USERNAME, ICINGA2_API_PASSWORD),
    headers=icinga2_hostnames_headers,
    json=icinga2_hostnames_data,
    verify=False)
icinga2_hostnames_json = icinga2_hostnames_request.json()['results']
icinga2_hostnames = []
for hostname in icinga2_hostnames_json:
    icinga2_hostnames.append(hostname['name'])
print('''Icinga2 returned %s hosts.
+------------------------------------------------------------------+''' % len(icinga2_hostnames))

# Read available measurements in selected DB
print('''+------------------------------------------------------------------+
Getting measurement list from InfluxDB''')
db_list_measurements_command = ['influx', '-database', INFLUX_DATABASE, '-execute',  'SHOW MEASUREMENTS', '-format', 'json' ]
db_list_measurements_result = subprocess.run(db_list_measurements_command, stdout=subprocess.PIPE)
db_measurements_json = json.loads(db_list_measurements_result.stdout.decode('utf-8'))['results'][0]['series'][0]['values']
db_measurements = []
for measurement in db_measurements_json:
    db_measurements.append(measurement[0])
print('''InfluxDB returned %s measurements.
+------------------------------------------------------------------+''' % len(db_measurements))

for measurement in db_measurements:
    print('''+------------------------------------------------------------------+
Cleaning up measurement %s''' % measurement)
    # Get hostnames in measurement
    measurement_list_hostnames_command = ['influx', '-database', INFLUX_DATABASE, '-execute',  'SHOW TAG VALUES FROM "%s" WITH KEY = "hostname"' % measurement, '-format', 'json' ]
    measurement_list_hostnames_result = subprocess.run(measurement_list_hostnames_command, stdout=subprocess.PIPE)
    measurement_hostnames_json = json.loads(measurement_list_hostnames_result.stdout.decode('utf-8'))['results'][0]
    if 'series' not in measurement_hostnames_json:
        # No hostnames in this measurement
        print('No hostnames in measurement %s.' % measurement)
        continue
    measurement_hostnames_json_series = measurement_hostnames_json['series'][0]['values']
    measurement_hostnames = []
    measurement_orphaned_hosts = []
    for hostname in measurement_hostnames_json_series:
        measurement_hostname = hostname[1]
        measurement_hostnames.append(measurement_hostname)
        if measurement_hostname not in icinga2_hostnames:
            print('Hostname %s does not exist in Icinga2!' % measurement_hostname)
            measurement_orphaned_hosts.append(measurement_hostname)
            if args.dryrun:
              print('Dry Run: would drop all series for host %s' % measurement_hostname)
            else:
              print('Dropping all series for host %s' % measurement_hostname)
              drop_series_command = ['influx', '-database', INFLUX_DATABASE, '-execute', 'DROP SERIES WHERE "hostname" = \'%s\'' % measurement_hostname ]
              drop_series_result = subprocess.run(drop_series_command, stdout=subprocess.PIPE)
              # Uncomment the line below to print output of DROP SERIES command, which is usually empty
              #print('DROP SERIES returned: %s' % drop_series_result.stdout.decode('utf-8'))
    print('''Measurement %s returned %s/%s orphaned/total hosts.
+------------------------------------------------------------------+''' % (measurement, len(measurement_orphaned_hosts), len(measurement_hostnames)))
