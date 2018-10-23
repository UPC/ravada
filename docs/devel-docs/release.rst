Steps to release
================

Create a branch
---------------

Name the branch following the guidelines of semantic versioning http://semver.org/:

MAJOR.MINOR.PATCH, increment the:

* MAJOR version when you make incompatible API changes,
* MINOR version when you add functionality in a backwards-compatible manner, and
* PATCH version when you make backwards-compatible bug fixes.


::

    $ git checkout master
    $ git checkout -b 0.2.2
    $ git push --set-upstream origin 0.2.2

Draft
-----

Draft the release
~~~~~~~~~~~~~~~~~

This step should be done at the very beginning of planning. If you already did it, skip it now.

At code -> releases draft a new release

-  tag version : v0.2.2
-  release title : v0.2.2

Create the milestone
--------------------

At the *issues* section , create a milestone. Name it like the tag
version: 0.2.2. There must be a way to link it to the *tag* , I just
don't know how.

Create issues
-------------

Assign issues to the milestone

Close
-----

Close the milestone
~~~~~~~~~~~~~~~~~~~

Check the milestone has no open issues and close it.

Update the authors
------------------

::

    $ git checkout 0.2.2
    $ cd templates/bootstrap/
    $ ./get_authors.sh

It will create a file *authors.html.ep*, review it and commit it.

::

    $ git commit authors.html.ep
    $ cd ../..

Update the release number
-------------------------

In Ravada.pm
~~~~~~~~~~~~

Modify *lib/Ravada.pm* around line 5:

::

    our $VERSION = '0.2.5';

Modify the Changelog
--------------------

Check the last issues closed for this milestone and add them to the
Changelog file:

::

    $ git checkout master
    $ gvim Changelog.md
    $ git commit -a



Close the release
-----------------

Make sure the target is the same as the branch, not the master. Close
the release at:

-  Close the Milestone
-  Publish the Release

Release binary
--------------

Debian
~~~~~~

Create the *debian* package.

::

    $ fakeroot ./deb/debianize.pl
    $ lintian ravada_0.2.2_all.deb

Upload the file to our repo and change the number at:

::

    http://ravada.readthedocs.io/en/latest/docs/INSTALL.html

    $ git checkout gh-pages
    $ gvim docs/docs/INSTALL.md
    $ gvim index.html
    $ git commit -a
    $ git push

Install it
----------
In a test machine, upgrade ravada following:

    http://ravada.readthedocs.io/en/latest/docs/update.html
    
In a fresh machine, install it following the whole process:

    http://ravada.readthedocs.io/en/latest/docs/INSTALL.html

Publish
-------

-  Tweet it
-  Mail it in google group ravada@groups.google.com
-  Change the release in branch master README.md
