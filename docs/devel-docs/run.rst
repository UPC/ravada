Run Ravada in development mode
------------------------------

Once it is installed, you have to run the two ravada daemons. One is the
web frontend and the other one runs as root and manage the virtual
machines.

Run scripts
===========

Both rvd_front and rvd_back must run. It is a good practice run each one in a different terminal.

The backend runs as root because it has to deal with the VM processes.
It won't reload automatically when there is a change, so it has to be
restarted manually when the code is modified:

.. prompt:: bash ~/src/ravada$

    sudo PERL5LIB=./lib ./script/rvd_back --debug

The web frontend runs with the ``morbo`` tool that comes with
*mojolicious*. It auto reloads itself if it detects any change in the
source code:

.. prompt:: bash ~/src/ravada$

     PERL5LIB=./lib morbo -m development -v ./script/rvd_front

Stop system Ravada
==================

You may have another copy of Ravada if you installed the package release.
**rvd_back** will complain if it finds there is another daemon running.
Stop it with:

::

    $ sudo systemctl stop rvd_back; sudo systemctl stop rvd_front

Run in fish
===========

If you use the fish shell you must run the scripts with these commands:

.. prompt:: bash ~/src/ravada$

    sudo PERL5LIB=./lib script/rvd_back --debug

.. prompt:: bash ~/src/ravada$

    set -x PERL5LIB ./lib ; morbo -m development -v script/rvd_front

