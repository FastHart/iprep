#!/bin/bash
echo "Content-Type: text/plain"
echo ""


MYSQL='/usr/bin/mysql -N -u iprep --password="" iprep'

printf "Database last updated (`/bin/date +"%Z %:::z"`): "
echo "select max(timestamp) from iprep;" | $MYSQL

printf "Total rows in rawdata table: "
echo "select count(*) from rawdata;" | $MYSQL

printf "Total scored IP's: "
echo "select count(*) from iprep;" | $MYSQL

printf "Total ip's with score above 80 (WHITE): "
echo "select count(*) from iprep where reputation >= 80;" | $MYSQL

printf "Total ip's with score little than 20 (BLACK): "
echo "select count(*) from iprep where reputation <= 20;" | $MYSQL

printf "Total ip's with scores in between: "
echo "select count(*) from iprep where reputation > 20 AND reputation < 80;" | $MYSQL

echo ""
echo "Top 25 spammers:"
echo "IP,       count of spam, reputation"
echo "select ip,spam,reputation from iprep where reputation <= 20 ORDER BY spam DESC LIMIT 25;" | $MYSQL

echo ""
echo "Top 25 hammers:"
echo "IP,      count of ham, reputation"
echo "select ip,ham,reputation from iprep where reputation >= 80 ORDER BY ham DESC LIMIT 25;" | $MYSQL
