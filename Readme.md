This script test the upgrade from all previous versions
to the current one.

Requirements
============

Packages
--------

sudo apt install mariadb-server libdbix-connector-perl libyaml-perl libdbd-mysql-perl libipc-run3-perl

Database
--------

After installing mysql or mariadb server create the Ravada database
just like when you install it.

```
sudo mysqladmin -u root -p create ravada
sudo mysql -u root -p ravada -e "create user 'rvd_user'@'localhost' identif
ied by 'Pword12345*'"
sudo mysql -u root -p ravada -e "grant all on ravada.* to 'rvd_user'@'localhost'"
```

Run the test
============

sudo ./test_upgrade.pl
