Steps to release
===============

# Draft

## Draft the release

At code -> releases draft a new release


 * tag version : v0.2.2
 * release title : v0.2.2


## Create the milestone

At the _issues_ section , create a milestone. Name it like the tag version: 0.2.2. There must be a way to link it to the _tag_ , I just don't know how.

## Create issues

Assign issues to the milestone

# Close

## Close the milestone

Check the milestone has no open issues and close it.

## Update the authors

    $ git checkout master
    $ cd templates/bootstrap/
    $ ./get_authors.sh

It will create a file _authors.html.ep_, review it and commit it.

    $ git commit authors.html.ep
    $ cd ../..

## Update the release number

### In Ravada.pm

Modify _lib/Ravada.pm_ around line 5:

    our $VERSION = '0.2.5';


## Modify the Changelog

Check the last issues closed for this milestone and add them to the Changelog file:

    $ git checkout master
    $ gvim Changelog.md
    $ git commit -a

## Create a branch

    $ git checkout master
    $ git checkout -b 0.2.2
    $ git push --set-upstream origin 0.2.2

## Close the release

Make sure the target is the same as the branch, not the master.
Close the release at:

- Close the Milestone
- Close the Release

# Release binary

## Debian

Create the _debian_ package.

    $ fakeroot ./deb/debianize.pl
    $ lintian ravaa_0.2.2_all.deb

Upload the file to our repo and change the number at:

    https://github.com/UPC/ravada/blob/master/docs/INSTALL.md

    $ git checkout master
    $ git merge v0.2.5
    $ gvim docs/INSTALL.md
    $ git commit -a
    $ git push

# Publish

- Tweet it
- Change the release in gh-pages

