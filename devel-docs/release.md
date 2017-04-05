Steps to release

#Draft

## Draft the release

At code -> releases draft a new release


 * tag version : aname.2
 * release title : 0.2.2

All the 0.2 releases are called _Aname_ , so 0.2.2 is _Aname.2_

## Create the milestone

Create a milestone called like the tag version: 0.2.2. There must be a way to link it to the _tag_ , I just don't know how.

## Create issues

Assign issues to the mileston

# Close

## Close the milestone

Check the milestone has no open issues and close it.

## Create a branch

    $ git checkout master
    $ git checkout -b aname.2
    $ git push --set-upstream origin aname.2

## Close the release

Make sure the target is the same as the branch, not the master
