Kiosk Mode
-----------

Kiosk ( or anonymous ) allows any user, not logged in, to create a volatile
virtual machine. This mode can be defined for some bases in some networks.

Setting
-------

Unfortunately kiosk mode configuration has not been added to the frontend.
Anyway it can be set only from within the database. Follow these steps carefully.

Backup the Database
-------------------

As we are going to change the database, any mistake can be fatal. Backup before.
If you want to have the data handy do it right now:

::

    # mysqldump -u root -p ravada domains.sql > domains.sql
    # mysqldump -u root -p ravada networks.sql > networks.sql

Define a Network
----------------

You can allow kiosk mode from any network, but you can define a new network where
this mode is allowed.

::

    # mysql -u root -p ravada
    mysql> insert into networks (name, address) values ('classroom','10.0.68.0/24');


Find the ids
------------

You must find what is the id of the network and the virtual machine where kiosk mode is enabled.

::

    mysql> select id,name from domains where name='blablabla';
    +----+-------------------+
    | id | name              |
    +----+-------------------+
    | 22 | blablabla         |
    +----+-------------------+
    mysql> select id,name from networks;
    +----+-----------+
    | id | name      |
    +----+-----------+
    |  1 | localnet  |
    |  4 | all       |
    |  6 | classroom |
    +----+-----------+



Allow anonymous mode
--------------------

::

    mysql> insert into domains_network(id_domain, id_network,anonymous) VALUES(33, 6, 1);


Access
------

Access now to the anonymous section in your ravada web server. http://your.ip:8081/anonymous

You should see there the base of the virtual machine you allowed before.

