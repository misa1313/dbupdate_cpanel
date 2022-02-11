#! /bin/sh

if [[ ! -f "/usr/local/cpanel/cpanel" ]]; then
	echo -e "This is intended to run on cPanel servers"
	kill -9 $$
else
	:
fi

#SQL mode
sqlm() {
echo -e "What's your username?"
read username
clear
if [[ ! -f "/etc/my.cnf.$username" ]]; then  
echo -e "\nBacking up the configuration file:"
cp -avr /etc/my.cnf /etc/my.cnf.$username
fi
echo -e "\n- SQL MODE:"
(grep -Eq 'sql_mode|sql-mode' /etc/my.cnf &&
echo -e "\e[1;92m[PASS] \e[0;32mSQL mode is set explicitly.\e(B\e[m\n" || 
(echo -e "Current effective setting is: sql_mode=\"$(mysql -NBe 'select @@sql_mode;')\"\e(B\e[m"
echo -e "Adding it to my.cnf..."
sql2=$(mysql -NBe 'select @@sql_mode;')
sed -i "6i sql_mode=\"$sql2"\" /etc/my.cnf
echo -e "Added, restarting MYSQL"
(systemctl restart mysql.service && echo -e "Restarted") || (/scripts/restartsrv_mysql > /dev/null && echo -e "Restarted*") || (service mysql restart > /dev/null && echo -e "Restarted**") || (service mysqld restart > /dev/null && echo -e "Restarted***")  
echo -e "Confirming: grep -E 'sql_mode|sql-mode' /etc/my.cnf"
grep -E 'sql_mode|sql-mode' /etc/my.cnf && echo -e "\nGiving a few secs for MYSQL to start\n" && sleep 3))
}

exe() { echo "\$ $@" ; "$@" ; }

#Stop the script
stopp() {
	echo -e "\nErrors have been detected. The script will stop. Run fg after you check to resume the script."
        kill -STOP $$
}

#Exit status
exit_status() {
e_status=`echo $?`
if [[ "$e_status" == "0" ]]; then
       : 
else
        stopp
fi
}

#Pre-work for 5.6-5.7/10.0
prepre() {
echo "Deprecated MySQL Variables 5.6 ---> 5.7: ";egrep -wi 'innodb\_additional\_mem\_pool\_size|safe\_show\_database|skip\_locking|skip\_symlink|master-*|log\-slow\-queries|innodb\_additional\_mem\_pool\_size|innodb\_use\_sys\_malloc|storage\_engine|create\_old\_temporals|default-authentication-plugin|thread_concurrency|timed\_mutexes|log-slow-admin-statements|log-slow-slave-statements' /etc/my.cnf;echo;echo "MySQL Datadir: ";mysql -e "show variables;" |grep datadir;echo;echo "Users with Old Style Passwords: "; if [[ $(mysql -e "SELECT Host, User, Password AS Hash FROM mysql.user WHERE Password REGEXP '^[0-9a-fA-F]{16}' ORDER BY User, Host;"|wc -l) > 0 ]];then echo "Yes";else echo "No"; echo; echo -e "\e[1;31mWARNING: MySQL 5.7's sys schema can break databases when upgrading to MariaDB\e[0m";fi; echo

echo -e "\n- Important variables:"
(set -x; mysql -e "show variables like '%innodb_additional_mem_pool_size'"; mysql -e "show variables like '%innodb_use_sys_malloc'"; mysql -e "show variables like '%storage_engine'"; mysql -e "show variables like '%create_old_temporals'"; mysql -e "show variables like '%default-authentication-plugin'"; mysql -e "show variables like '%thread_concurrency'"; mysql -e "show variables like '%timed_mutexes'"; mysql -e "show variables like '%log-slow-admin-statements'"; mysql -e "show variables like '%log-slow-slave-statements'";) 
}

#Pre-checks and backups
pre_checks() {
    
   echo -e "\n- Checking for corruption:"
    mychecktemp=$(mysqlcheck -Asc)
    echo -e "\nmysqlcheck -Asc"
    if [[ -z "$mychecktemp" ]]; then
    echo -e "\nNo output. All good.\n"
    else
        echo $mychecktemp
        mychecktemp2=$(echo $mychecktemp | grep -iE "corrupt|crashe" )
        if [[ ! -z "$mychecktemp2" ]]; then 
              stopp
	else 
		echo -e "\nMinor errors/warnings\n" 
	fi
    fi
 
    echo -e "- Backups:\n"
    if [[ ! -d "/home/temp/mysqldumps.$username" ]]; then 
	    mkdir /home/temp/mysqldumps.$username
    fi
    cd /home/temp/mysqldumps.$username
    (set -x; pwd)
    echo
    exe eval '(echo "SHOW DATABASES;" | mysql -Bs | grep -v '^information_schema$' | while read i ; do echo Dumping $i ; mysqldump --single-transaction $i | gzip -c > $i.sql.gz ; done)'
    echo
    error='0';count='';for f in $(/bin/ls *.sql.gz); do if [[ ! $(zegrep 'Dump completed on [0-9]{4}-([0-9]{2}-?){2}' ${f}) ]]; then echo "Possible error: ${f}"; error=$((error+1)); fi ; count=$((count+1)); done; (echo "Error count: ${error}"; echo "Total DB_dumps: ${count}"; echo "Total DBs: $(mysql -NBe 'SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE schema_name NOT IN ("information_schema");')";)|column -t
    if [[ "$error" != 0 ]]; then
    stopp
    fi     
 
    echo -e "\nRsync data dir:\n"
    ddir=$(mysql -e "show variables;" |grep datadir| awk {'print $2'})
    bakdir=$(echo "$ddir"|rev | cut -c2-|rev)
    (systemctl stop mysql.service && echo -e "MYSQL has been stopped") || (service mysql stop > /dev/null && echo -e "MYSQL has been stopped*") || (service mysqld stop > /dev/null && echo -e "MYSQL has been stopped**")
    sleep 1 && echo
    echo "Path to data dir: $ddir"
    echo "rsync -aHl $ddir $bakdir.backup/"
    rsync -aHl $ddir $bakdir.backup/
    exit_status
    echo -e "Synced\n" 
    echo "Restarting MYSQL..."
    (systemctl restart mysql.service && echo -e "Restarted") || (/scripts/restartsrv_mysql > /dev/null && echo -e "Restarted*") || (service mysql restart > /dev/null && echo -e "Restarted**") || (service mysqld restart > /dev/null && echo -e "Restarted***")
    sleep 3

    echo -e "\n\n-Checking HTTP status of all domains prior the upgrade:\n"
    if [[ ! -d "/home/temp" ]]; then
    	mkdir /home/temp
    fi
    sort /etc/userdomains | cut -f1 -d: | grep -v '*' | while read i; do curl -sILo /dev/null -w "%{http_code} " -m 5 http://$i; echo $i; done > /home/temp/mysql_pre_upgrade_http_check
    (set -x; egrep -v '^(0|2)00 ' /home/temp/mysql_pre_upgrade_http_check)
    echo -e "\n- WHM upgrade: MySQL/MariaDB Upgrade"
}

#Execution
upgrade_do() {
echo -e "List of available versions:\n"
/usr/local/cpanel/bin/whmapi1 installable_mysql_versions| grep "version: '"
echo -e "\nWhich one are you installing? Only numbers (5.7, 10.3, etc.)"
read vers
while true; do 
 	if  [[ "$vers" == '10.1' ]] || [[ "$vers" == '10.2' ]] || [[ "$vers" == '10.3' ]] || [[ "$vers" == '10.5' ]] || [[ "$vers" == '5.6' ]] || [[ "$vers" == '5.7' ]] || [[ "$vers" == '8.0' ]]; then
	#check here add vers
	    break
	else
            echo "Invalid option, choose again."
	    read vers
	fi
done
 
id=$(/usr/local/cpanel/bin/whmapi1 start_background_mysql_upgrade version=$vers|grep "upgrade_id" | cut -d ":" -f2)
id="${id:1}"
echo -e "\nWHM Upgrade ID: $id"
sleep 1
aver=$(/usr/local/cpanel/bin/whmapi1 background_mysql_upgrade_status upgrade_id=$id| tail -n6|grep "state:"| cut -d ":" -f2| awk '{print $1;}')
echo -e "\nUpgrading..."
BAR='#'
while [[ "$aver" == "inprogress" ]]; do
	echo -ne "${BAR}"
	sleep 2
        aver=$(/usr/local/cpanel/bin/whmapi1 background_mysql_upgrade_status upgrade_id=$id| tail -n6|grep "state:"| cut -d ":" -f2| awk '{print $1;}')
done
sleep 2
if [[ "$aver" == "failed" || "$aver" == "failure" ]]; then
	echo -e "\nCheck the log at /var/cpanel/logs/$id/unattended_background_upgrade.log"
	stopp
else
echo -e "\n"
/usr/local/cpanel/bin/whmapi1 background_mysql_upgrade_status upgrade_id=$id| tail -n6
fi
}

#Postcheck
post_check(){
sleep 1
echo -e "\n\nPost-check:\n"
sort /etc/userdomains | cut -f1 -d: | grep -v '*' | while read i; do curl -sILo /dev/null -w "%{http_code} " -m 5 http://$i; echo $i; done > /home/temp/mysql_post_upgrade_http_check
exe eval 'diff /home/temp/mysql_pre_upgrade_http_check /home/temp/mysql_post_upgrade_http_check'
echo -e "\nAll set.\n"
}

#MYSQL version & Procedure:
mysqlv=$(mysql -V | grep -Eo "[0-9]+\.[0-9]+\.[0-9]+";)
if [[ "$(cat /etc/redhat-release)" == *"CloudLinux"* ]]; then
    sqlm
    echo "System version is $mysqlv, this would be the installation for CloudLinux"
    pre_checks
    echo -e "Is this server using MySQL Governor? y/n"
    read answ
    if [[ $answ == "yes" || $answ == "Yes" || $answ == "YES" || $answ == "y" ]]; then
    	echo -e "\nTo which version you want to upgrade?\nOptions:\n\nMYSQL:\nmysql55, mysql56, mysql57, mysql80\n\nMariaDB:\nmariadb100, mariadb101, mariadb102, mariadb103\n"
    	read answ2
    	echo $answ2
    	echo -e "\nUpgrade using governor:"
    	exe eval '/usr/share/lve/dbgovernor/mysqlgovernor.py --mysql-version=$answ2'
    	exe eval '/usr/share/lve/dbgovernor/mysqlgovernor.py --install --yes'
	exe eval 'mysql_upgrade'
    else
    	echo "Ok, cPanel upgrade then."
    	upgrade_do
    fi
    post_check

elif [[ "$mysqlv" == "5.6."* || "$mysqlv" == "10.0."* ]]; then
    sqlm
    echo "System version is $mysqlv"
    prepre
    pre_checks
    upgrade_do
    post_check

elif [[ "$mysqlv" == "5.7."* ]]; then
    sqlm 
    echo "System version is $mysqlv"
    prepre
    echo -e "\nUpgrade checker:"
    echo -e "\nInstalling mysql-shell\n"
    _centos_version=$(rpm -q kernel | head -1 | grep -Po '(?<=el)[0-9]')
    if [ "$_centos_version" == 8 ]; then
	_repo_rpm="https://dev.mysql.com/get/mysql80-community-release-el8-1.noarch.rpm"
    elif [ "$_centos_version" == 7 ]; then
	_repo_rpm="https://dev.mysql.com/get/mysql80-community-release-el7-3.noarch.rpm"
    elif [ "$_centos_version" == 6 ]; then
	_repo_rpm="https://dev.mysql.com/get/mysql80-community-release-el6-3.noarch.rpm"
    fi
    (yum -y install $_repo_rpm && yum-config-manager --disable mysql80-community mysql-connectors-community mysql-tools-community
    yum -y --enablerepo=mysql-tools-community install mysql-shell) 2>&1 > /dev/null
    mysql_pass=$(sed -nre '/password/s/^ *password *= *"?([^"]+)"? *$/\1/gp' /root/.my.cnf)
    if [[ -z "$mysql_pass" ]]; then
	echo "The password could not be retrieved, try to find it to resume the script" 
	stopp
    fi
    echo
    if [[ -z "$mysql_pass" ]]; then
	echo "Enter the password"
	read mysql_pass
    fi
    pre_checks
    echo
(set -x; mysqlsh -hlocalhost -uroot --password=$mysql_pass -e 'util.checkForServerUpgrade()')
    echo -e "\nIf you see any errors (warnings are usually safe to ignore), pause the script with Ctrl+z."
    upgrade_do
    post_check

elif [[ "$mysqlv" == "10.1."* || "$mysqlv" == "10.2."* || "$mysqlv" == "10.3."* ]]; then
    sqlm
    echo "System version is $mysqlv"
    pre_checks
    upgrade_do
    post_check
    
elif [[ "$mysqlv" == "10.5."* || "$mysqlv" == "8.0."* ]]; then
    echo -e "You are already on the latest version.\n"
else 
    echo -e "This is a not supported upgrade.\n"
fi
