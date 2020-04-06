Run Ravada in development mode
------------------------------

Once it is installed, you have to run the two ravada daemons. One is the
web frontend and the other one runs as root and manage the virtual
machines. It is a good practice run each one in a different terminal:

The web frontend runs with the ``morbo`` tool that comes with
*mojolicious*. It auto reloads itself if it detects any change in the
source code:

::

    ~/src/ravada$ PERL5LIB=./lib morbo ./script/rvd_front

The backend runs as root because it has to deal with the VM processes.
It won't reload automatically when there is a change, so it has to be
restarted manually when the code is modified:

::

    ~/src/ravada$ sudo PERL5LIB=./lib ./script/rvd_back --debug

Stop system Ravada
==================

You may have another copy of Ravada if you installed the package release.
**rvd_back** will complain if it finds there is another daemon running.
Stop it with:

::

    $ sudo systemctl stop rvd_back; sudo systemctl stop rvd_front

Keep the library up to date
===========================
If you change of branch you may have old libraries running, clean it up from
the ravada source directory with:

::

    ~/src/ravada$ sudo make clean

