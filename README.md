# icinga2-cleanup-influxdb
This script can be used to cleanup unused Icinga2 data in InfluxDB.

The process is as follows:

- collect list of hostnames present in Icinga2 via REST API
- collect all measurements in Icinga2’s InfluxDB
- collect all hostnames within a measurement
- check if each hostname is still present in Icinga2, if not, drop ALL series for that host

Requirements
---
- python3 (tested with python 3.6.8)
- python-requests (tested with 2.22.0)
- influx binary in $PATH

Usage
---

- modify the following variables in the script as needed:
  - INFLUX_DATABASE
  - ICINGA2_API_URL
  - ICINGA2_API_USERNAME
  - ICINGA2_API_PASSWORD
- run the script as root user on your InfluxDB host

Notes
---

**Run this at your own risk and create backups if your InfluxDB contains critical data!**  

Depending on the amount of series to be dropped, this script can be quite IO-intensive.  

Influx tries to compact its files as soon as a DROP SERIES command is issued.  
If another DROP SERIES command is issued before the compaction is finished, the compaction will be aborted which causes corresponding messages in the InfluxDB log.  
This is no issue, as the compaction will run again after this script is finished.
