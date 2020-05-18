Mysql Database
--------------

Ravada needs a MySQL database to store information.

MySQL server
~~~~~~~~~~~~
.. Warning::  MySql required minimum version 5.6

It is required a MySQL server, it can be installed in another host or in
the same one as the ravada package.

Ubuntu based distros

.. prompt:: bash $

     sudo apt-get install mysql-server

Debian based distros

.. prompt:: bash $

     sudo apt-get install mariadb-server

RedHat and Fedora based distros

.. prompt:: bash $

     sudo dnf install mariadb mariadb-server
     sudo systemctl enable --now mariadb.service
     sudo systemctl start mariadb.service

After completion of mysql installation, run command:

.. prompt:: bash $

     sudo mysql_secure_installation


MySQL database and user
~~~~~~~~~~~~~~~~~~~~~~~

It is required a database for internal use. In this examples we call it *ravada*.
We also need an user and a password to connect to the database. It is customary to call it *rvd_user*.
In this stage the system wants you to set a password for the sql connection.

.. Warning:: When installing MySQL you wont be asked for a password, you can set a password for the root user in MySQL via *mysql_secure_installation* or type your user's password when it ask's you for a password.

Create the database:

.. prompt:: bash $

     sudo mysqladmin -u root -p create ravada

Grant all permissions on this database to the *rvd_user*:

.. prompt:: bash $

     sudo mysql -u root -p ravada -e "create user 'rvd_user'@'localhost' identified by 'Pword12345*'"
     sudo mysql -u root -p ravada -e "grant all on ravada.* to rvd_user@'localhost'"

The password chosen must fulfill the following characteristics:

    - At least 8 characters.
    - At least 1 number.
    - At least 1 special character.


