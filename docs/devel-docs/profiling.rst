Profiling Ravada
================

If you think a process takes much more than it should or you want
to check where time is spent the NYT Perl Profiler is very easy to use.

Just follow these steps:

Services
--------

Start the *rvd_front* service but **stop** *rvd_back*. We will start it
again later with profiling enabled.

Request
-------

Remove the requests from the database:

::

    mysql> delete from requests;

Click on the web admin to run the request you want to check. It should appear
now in the requests table:

::

    mysql> select id,command from requests;

Run rvd_back
------------

Run the *rvd_back* service with profiling enabled, and make it stop when it
reaches the request you want to profile. You found the request id in the previous
step:

.. prompt:: bash $

   sudo perl -d:NYTProf bin/rvd_back.pl --no-fork --debug --run-request=148


Profile files
-------------

Create the profiling files with these commands:

.. prompt:: bash $

   nytprofcg
   kcachegrind nytprof.callgrind

Sort it by self to see where the time is spent on.

More info
---------

Find out more about NYTProf profiler in these
`slides <https://www.slideshare.net/Tim.Bunce/develnytprof-v4-at-yapceu-201008-4906467>`_.
