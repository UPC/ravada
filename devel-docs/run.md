Run Ravada in development mode
------------------------------

Once it is installed, you have to run the two ravada daemons. One is the web
frontend and the other one runs as root and manage the virtual machines.
It is a good practice run each one in a different terminal:

The web frontend runs with the `morbo` tool that comes with _mojolicious_. It
auto reloads itself if it detects any change in the source code:

    ~/src/ravada$ morbo -v ./rvd_front.pl


The backend runs as root because it has to deal with the VM processes. It won't
reload automatically when there is a change, so it has to be restarted manually
when the code is modified:

    ~/src/ravada$ sudo ./bin/rvd_back.pl --debug

