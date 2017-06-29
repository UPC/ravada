## Contributing

First off, thank you for considering contributing to Ravada. It's people
like you that make it such a great tool.

### 1. Where do I go from here?

If you've noticed a bug or have a question that doesn't belong on the
[mailing list](http://groups.google.com/group/ravada)
or
[search the issue tracker](https://github.com/UPC/ravada/issues?q=something)
to see if someone else in the community has already created a ticket.
If not, go ahead and [make one](https://github.com/UPC/ravada/issues/new)!

### 2. Fork & create a branch

If this is something you think you can fix, then
[fork Ravada](https://help.github.com/articles/fork-a-repo)
and create a branch with a descriptive name.

A good branch name would be (where issue #325 is the ticket you're working on):

```sh
git checkout -b 325_boost_performance
```

If you contribute code, *thank you* ! Plase, follow this rules so our
code is in sync:

- Use spaces, don't do tabs.
- Add the issue number at the very beggining of the commit message
``[#44] Fixed flux capacitor leak``

### 3. Get the tests running

See this documentation about [testing](http://ravada.readthedocs.io/en/latest/devel-docs/commit-rules.html#testing) the project.

#### 4. Did you find a bug?

* **Ensure the bug was not already reported** by searching on GitHub under [Issues](https://github.com/UPC/ravada/issues).

* If you're unable to find an open issue addressing the problem, [open a new one](https://github.com/UPC/ravada/issues/new).
Be sure to include a **title and clear description**, as much relevant information as possible,
and a **code sample**, an **executable test case** or a step by step guide demonstrating the expected behavior that is not occurring.

### 5. Implement your fix or feature

At this point, you're ready to make your changes! Feel free to ask for help;
everyone is a beginner at first :smile_cat:

Follow this guide about running [Ravada in development mode](http://ravada.readthedocs.io/en/latest/devel-docs/run.html).

### 6. Make a Pull Request

At this point, you should switch back to your master branch and make sure it's
up to date with Ravada's master branch:

```sh
git remote add upstream git@github.com:UPC/ravada.git
git checkout master
git pull --rebase origin master
```

Then update your feature branch from your local copy of master, and push it!

```sh
git checkout 325_boost_performance
git rebase master
git push --set-upstream origin 325_boost_performance
```

Finally, go to GitHub and
[make a Pull Request](https://help.github.com/articles/creating-a-pull-request)
:D

### 7. Keeping your Pull Request updated

If a maintainer asks you to "rebase" your PR, they're saying that a lot of code
has changed, and that you need to update your branch so it's easier to merge.

To learn more about rebasing in Git, there are a lot of
[good](http://git-scm.com/book/en/Git-Branching-Rebasing)
[resources](https://help.github.com/articles/interactive-rebase),
but here's the suggested workflow:

```sh
git checkout 325_boost_performance
git pull --rebase upstream master
git push --force-with-lease origin 325_boost_performance
```

### 8. Merging a PR (maintainers only)

A PR can only be merged into master by a maintainer if:

* It is passing CI.
* It has been approved by at least one admin.
* It has no requested changes.
* It is up to date with current master.

Any maintainer is allowed to merge a PR if all of these conditions are
met.
