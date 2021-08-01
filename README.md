# mysql_auto

A bash script to automatically upgrade the database management system on cPanel servers. Tested on CentOS 6 and 7.


## Usage:

1. Enter any username (this is for reference).
2. Select the proper MYSQL/MariaDB version:
```
    5.7 (MySQL)
    8.0 (MySQL)
    10.1 (MariaDB)
    10.2 (MariaDB)
    10.3 (MariaDB)
```

## Features:

The script will first check the SQL mode to set it explicitly in the my.cnf file (if it's not already there), then it will check for corruption, dump all the databases, back up the data dir, and lastly proceed with the upgrade. The script will be automatically stopped if an issue is detected during the backup or upgrade process. 
