Commit Rules
============

Main Branches
-------------

The main branches are *master* and *develop* as described here:

http://nvie.com/posts/a-successful-git-branching-model/

Issues
------

Please create a new branch for each issue. Also it would be a good idea
to call the branch with the number of the issue and a short text, ie:

.. prompt:: bash $

   git checkout -b 77_crashonstart

Commit Message
--------------

We use conventional commits guideline as specified in https://conventionalcommits.org/
Each commit must be for a reason, and we should have an issue for that, so we decided
to add the issue number in the footer.

Definition:

::

    <type>[optional scope]: <description>
    
    [optional body]
    
    footer #issue


Example:

::

    fix: active virtual machines can not be started

    When a virtual machine is already active, do not try to start it and return

    #77



Show the branch in the message
------------------------------

Add the file *prepare-commit-msg* to the directory *.git/hooks/* with
this content:

.. note:: Remember to give permission to execute, ``chmod a+x prepare-commit-msg``

::

    #!/bin/sh
    #
    # Automatically adds branch name and branch description to every commit message.

    #
    NAME=$(git branch | grep '*' | sed 's/* //')
    DESCRIPTION=$(git config branch."$NAME".description)
    TEXT=$(cat "$1" | sed '/^#.*/d')

    if [ -n "$TEXT" ]
    then
        echo "$NAME"': '$(cat "$1" | sed '/^#.*/d') > "$1"
        if [ -n "$DESCRIPTION" ]
        then
           echo "" >> "$1"
           echo $DESCRIPTION >> "$1"
        fi
    else
        echo "Aborting commit due to empty commit message."
        exit 1
    fi

Testing
-------

Before committing, make sure it passes all the tests. This should be run
specially when changing the *master* and *develop* branches. Notice some
tests require *root* access, so it must run with *sudo*.

.. prompt:: bash $

   perl Makefile.PL && make && sudo make test
    
If you want to run only one test:

.. prompt:: bash $

   perl Makefile.PL && make && sudo prove -b t/dir/file.t

Proper testing requires the Perl Module Test::SQL::Data, available here: https://github.com/frankiejol/Test-SQL-Data

Contribution Guide
------------------

Check our contribution guide for more information about this topic.

https://github.com/UPC/ravada/blob/master/CONTRIBUTING.md
