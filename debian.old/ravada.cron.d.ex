#
# Regular cron jobs for the ravada package
#
0 4	* * *	root	[ -x /usr/bin/ravada_maintenance ] && /usr/bin/ravada_maintenance
