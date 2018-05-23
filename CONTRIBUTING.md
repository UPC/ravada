# Contributing

First off, thank you for considering contributing to Ravada. It's people
like you that make it such a great tool.

## 1. Where do I go from here?

If you've noticed a bug or have a question that doesn't belong on the
[mailing list](http://groups.google.com/group/ravada)
or
[search the issue tracker](https://github.com/UPC/ravada/issues?q=something)
to see if someone else in the community has already created a ticket.
You can also ask in our [telegram public group](https://t.me/ravadavdi).
If it is not, go ahead and [create a new issue](https://github.com/UPC/ravada/issues/new)!

## 2. Fork & create a branch

If this is something you think you can fix, then
[fork Ravada](https://help.github.com/articles/fork-a-repo)
and create a branch with a descriptive name. We prepend the issue number to
the branch so it is easier to follow.

A good branch name would be (where issue #77 is the one you're working on):

```sh
git checkout -b 77_start_machine
```

## 3. Code Style

See our
[editor configuration](http://ravada.readthedocs.io/en/latest/devel-docs/editor-rules.html)
guidelines so your code gets along with old code. A recurrent problem for newcommers
is to submit code automatically cleaned by the editor. Usually, removed end of line
spaces or spaces converted to tabs.
Please make sure you don't do that. Run ``git diff`` before commit to see what you are
exactly contributing.

## 4. Commit Format

If you contribute code, *thank you* ! Plase, follow this guide.

Each commit message consists of a header, a body, and a footer. The header has a special format that includes a type, a scope, and a description.
We use [conventional commits](https://conventionalcommits.org/) format. Each commit must be for
a reason, and we should have an [issue](https://github.com/UPC/ravada/issues) for that, so we
decided to add the issue number in the footer.

The commit message should be structured as follows:

```
type(optional scope): description
<blank line>
optional body
<blank line>
footer #issue
```

Example:
```
fix: active virtual machines can not be started

check the machine status before start
returns if machine active
before it crashed trying to start the machine

fixes #77
```

### 4.1 Header: Type

Commits must be prefixed with a type, which consists of a verb, feat, fix, build, followed by a colon and space.

Your options:

- build: Changes that affect the build system or external dependencies (example scopes: gulp, broccoli, npm).
- ci: Changes to our CI configuration files and scripts (example scopes: Travis, Circle, BrowserStack, SauceLabs).
- docs: Documentation only changes.
- feat: A new feature.
- fix: A bug fix.
- perf: A code change that improves performance.
- refactor: A code change that neither fixes a bug or adds a feature.
- style: Changes that do not affect the meaning of the code (white-space, formatting, missing semi-colons, etc).
- test: Adding missing tests or correcting existing tests.

### 4.2 Header: Optional Scope

Refers to the extent, subject matter or contextual information about your changes. A scope is a phrase describing the file modified or a section of the codebase, it is always enclosed in parenthesis.

Example for a (optional scope):

    feat(parser): add ability to parse arrays

### 4.3 Header: Description

A description must immediately follow the type(optional scope): The description is a short description of the commit.

Important:

 - About commit character length, keep it concise and don't write more than 50 characters.
 - Use the imperative present tense: change, make, add, update, fix, etc; Do not use changed,
    changes, added, fixes, fixed, etc.
 - Don't capitalize the first letter.
 - Do not use a dot (.) at the end.

### 4.4 Header Lenghth

The header cannot be longer than 100 characters. This allows the message to be easier to read on GitHub as well as in various git tools.

### 4.5 Writing the optional body

The body should include the motivation for the change and contrast this with previous behavior.

Example for optional body:

```
fix orthography
remove out of date paragraph
fix broken links
 ```

### 4.5 Writing the optional footer

The <optional footer> should contain a closing reference to an issue if any.

For example, to close an issue numbered 123, you could use the phrases Closes #123 in your
pull request description or commit message. Once the branch is merged into the default branch,
the issue will close.


## 5. Get the tests running

See this documentation about [testing](http://ravada.readthedocs.io/en/latest/devel-docs/commit-rules.html#testing) the project.

## 6. Did you find a bug?

* **Ensure the bug was not already reported** by searching on GitHub under [Issues](https://github.com/UPC/ravada/issues).

* If you're unable to find an open issue addressing the problem, [open a new one](https://github.com/UPC/ravada/issues/new).
Be sure to include a **title and clear description**, as much relevant information as possible,
and a **code sample**, an **executable test case** or a step by step guide demonstrating the expected behavior that is not occurring.

## 7. Implement your fix or feature

At this point, you're ready to make your changes! Feel free to ask for help;
everyone is a beginner at first :smile_cat:

Follow this guide about running [Ravada in development mode](http://ravada.readthedocs.io/en/latest/devel-docs/run.html).

If you change a translation or language file make sure you follow this small [guide](http://ravada.readthedocs.io/en/latest/devel-docs/translations.html?highlight=translate) and don't forget to add the issue number when committing.

## 8. Push your changes

Pushing refers to sending your committed changes to a remote repository, such as a repository
hosted on GitHub. Before that all the changes where local in the computer you are working in.

After working on your changes you need to Push it (upload) your newly created branch to GitHub

    git push

## 9. Create a Pull Request

Pull requests or PR are proposed changes to a repository submitted by a user and accepted or rejected by a repository's collaborators.

When your changes are done, you should switch back to your master branch and make sure it's
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

Finally, go to our GitHub repository and
[create a Pull Request](https://github.com/UPC/ravada/pulls)

### 9.1 How to Write a Title for a Pull Request

Pull Request should be named in reference to the main fix or feature you provide; minor information can be added to the description. Please be specific and don't use generic terms.
Keep it concise and don't write more than 50 characters in the title.

Read [more information about PR](https://help.github.com/articles/creating-a-pull-request)


### 9.2 Keeping your Pull Request updated

If a maintainer asks you to "rebase" your PR, they're saying that a lot of code
has changed, and that you need to update your branch so it's easier to merge.

To learn more about rebasing in Git, there are a lot of
[good](http://git-scm.com/book/en/Git-Branching-Rebasing)
[resources](https://help.github.com/articles/interactive-rebase),
but here's the suggested workflow:

```sh
git checkout 325_boost_performance
git pull --rebase origin master
git push --force-with-lease origin 325_boost_performance
```

### 9.3 Merging a PR (maintainers only)

A PR can only be merged into master by a maintainer if:

* It is passing CI.
* It has been approved by at least one admin.
* It has no requested changes.
* It is up to date with current master.

Any maintainer is allowed to merge a PR if all of these conditions are
met.
