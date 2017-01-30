Commit Rules
=============



Main Branches
-------------

The main branches are _master_ and _develop_ as described here:

http://nvie.com/posts/a-successful-git-branching-model/

Issues
------

Please create a new branch for each issue. Also it would be a good idea to call the branch with the number of the issue and a short text, ie:

    git checkout -b 77_crashonstart
   

Testing
-------

Before committing, make sure it passes all the tests. This should be run specially when chaning the _master_ and _develop_ branches. Notice some tests require _root_ access, so it must run with _sudo_.

    perl Makefile.PL && make && sudo make test
