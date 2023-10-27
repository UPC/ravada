Rollback Ravada Version
=======================

If you just upgraded Ravada and want to go to a previous version follow these steps:

Restore Database
----------------

This may not be necessary, try to install first the previous Ravada version and
see if everything works. Anyway if you want to restore the database you must have
a backup file.

.. prompt:: bash

   mysql -u rvd_user -p ravada < ravada.sql

Install previous version
------------------------

.. prompt:: bash

   sudo dpkg -i ravada_version.deb

Restart the services
--------------------

.. prompt:: bash

    sudo systemctl restart rvd_back
    sudo systemctl restart rvd_front

