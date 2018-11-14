Kiosk Mode
==========

Kiosk ( or anonymous ) allows any user, not logged in, to create a volatile
virtual machine. Once this machine is shut down, it is destroyed automatically.

This feature is only available on Ravada 0.3. You can get it from here:

http://infoteleco.upc.edu/img/debian/

Setting
-------

This *kiosk* mode must be defined for some bases in some networks.


.. note ::
    Unfortunately kiosk mode configuration has not been added to the frontend.
    Anyway it can be set only from within the database. 
    
Follow these steps carefully.

Backup the Database
-------------------

As we are going to change the database, any mistake can be fatal. Backup before.
If you want to have the data handy do it right now:

.. prompt:: bash #

    mysqldump -u root -p ravada domains > domains.sql
    mysqldump -u root -p ravada networks > networks.sql

Define a Network
----------------

You can allow kiosk mode from any network, but you can define a new network where
this mode is allowed.

.. prompt:: bash #,(env)... auto

    # mysql -u root -p ravada
    mysql> insert into networks (name, address) values ('classroom','10.0.68.0/24');


Find the ids
------------

You must find what is the id of the network and the virtual machine where kiosk mode is enabled.
This domain must be a base and allowed public access.

::

    mysql> select id,name from domains where name='blablabla' and is_base=1 and is_public=1;
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

