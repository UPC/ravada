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

## 2. Source code

We manage the code with Git. If you already know it, skip this point. If this is the
first time you work with it, beware it has a learning curve. First of all read some
introduction. Then please ask questions if you need it, we are more than willing to
mentor first timers.

* Join the [Ravada Google group](https://groups.google.com/forum/#!forum/ravada).
* Meet us in our [Telegram public group](http://t.me/ravadavdi).


## 3. Fork & create a branch

If this is something you think you can fix, then
[fork Ravada](https://help.github.com/articles/fork-a-repo)

## 4. Code Style

See our
[editor configuration](http://ravada.readthedocs.io/en/latest/devel-docs/editor-rules.html)
guidelines so your code gets along with old code. A recurrent problem for newcommers
is to submit code automatically cleaned by the editor. Usually, removed end of line
spaces or spaces converted to tabs.
Please make sure you don't do that. Run ``git diff`` before commit to see what you are
exactly contributing.

## 5. Commit Format

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
fix(backend): active virtual machines can not be started

check the machine status before start
returns if machine active
before it crashed trying to start the machine

fixes #77
```

### 5.1 Header: Type

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
- wip: Work in Progress
- test: Adding missing tests or correcting existing tests.

### 5.2 Header: Optional Scope

Refers to the extent, subject matter or contextual information about your changes. A scope is a phrase describing the file modified or a section of the codebase, it is always enclosed in parenthesis.

Example for a (optional scope):

    feat(parser): add ability to parse arrays

### 5.3 Header: Description

A description must immediately follow the type(optional scope): The description is a short description of the commit.

Important:

 - About commit character length, keep it concise and don't write more than 50 characters.
 - Use the imperative present tense: change, make, add, update, fix, etc; Do not use changed,
    changes, added, fixes, fixed, etc.
 - Don't capitalize the first letter.
 - Do not use a dot (.) at the end.

### 5.4 Header Lenghth

The header cannot be longer than 100 characters. This allows the message to be easier to read on GitHub as well as in various git tools.

### 5.5 Writing the optional body

The body should include the motivation for the change and contrast this with previous behavior.

Example for optional body:

```
fix orthography
remove out of date paragraph
fix broken links
 ```

### 5.6 Writing the optional footer

The <optional footer> should contain a closing reference to an issue if any.

For example, to close an issue numbered 123, you could use the phrases Closes #123 in your
pull request description or commit message. Once the branch is merged into the default branch,
the issue will close.


## 6. Get the tests running

See this documentation about [testing](http://ravada.readthedocs.io/en/latest/devel-docs/commit-rules.html#testing) the project.

## 7. Did you find a bug?

* **Ensure the bug was not already reported** by searching on GitHub under [Issues](https://github.com/UPC/ravada/issues).

* If you're unable to find an open issue addressing the problem, [open a new one](https://github.com/UPC/ravada/issues/new).
Be sure to include a **title and clear description**, as much relevant information as possible,
and a **code sample**, an **executable test case** or a step by step guide demonstrating the expected behavior that is not occurring.

## 8. Implement your fix or feature

At this point, you're ready to make your changes! Feel free to ask for help;
everyone is a beginner at first :smile_cat:

Follow this guide about running [Ravada in development mode](http://ravada.readthedocs.io/en/latest/devel-docs/run.html).

If you change a translation or language file make sure you follow this small [guide](http://ravada.readthedocs.io/en/latest/devel-docs/translations.html?highlight=translate) and don't forget to add the issue number when committing.

## 9. Push your changes

Pushing refers to sending your committed changes to a remote repository, such as a repository
hosted on GitHub. Before that all the changes where local in the computer you are working in.

After working on your changes you need to Push it (upload) your newly created branch to GitHub

    git push

## 10. Create a Pull Request

Pull requests or PR are proposed changes to a repository submitted by a user and accepted or rejected by a repository's collaborators.


Send your changes to github *pushing* them up:

```sh
git push
```

Finally, go to your GitHub repository and
[create a Pull Request](https://github.com/pulls)

### 10.1 How to Write a Title for a Pull Request

Pull Request should be named in reference to the main fix or feature you provide; minor information can be added to the description. Please be specific and don't use generic terms.
Keep it concise and don't write more than 50 characters in the title.

Read [more information about PR](https://help.github.com/articles/creating-a-pull-request)


### 10.2 Keeping your Pull Request updated

If a maintainer asks you to "rebase" your PR, they're saying that a lot of code
has changed, and that you need to update your branch so it's easier to merge.

To learn more about rebasing in Git, there are a lot of
[good](http://git-scm.com/book/en/Git-Branching-Rebasing)
[resources](https://help.github.com/articles/interactive-rebase),
but here's the suggested workflow:

```sh
git remote add upstream https://github.com/UPC/ravada.git
git fetch upstream
git rebase upstream/develop
```

### 10.3 Merging a PR (maintainers only)

A PR can only be merged into master by a maintainer if:

* It is passing CI.
* It has been approved by at least one admin.
* It has no requested changes.
* It is up to date with current master.

Any maintainer is allowed to merge a PR if all of these conditions are
met.

## 11 Reset my fork to upstream

You may want to ditch everything in your fork

### 11.1 Reset develop branch

 If you want to get even with main develop branch.

```sh
git remote add upstream git@github.com:UPC/ravada.git
git fetch upstream
git checkout main
git reset --hard upstream/main
git push origin main --force
```

### 11.2 Work in a new fresh branch

We create a new branch called *feature/cool_thing* and make it exactly like UPC/develop branch:

First we add the upstream remote source and fetch it. If you added this remote before you will get an error *fatal: remote upstream already exists.*. Don't worry and run the `git fetch upstream` anyway so it downloads the UPC source.

```sh
git remote add upstream https://github.com/UPC/ravada
git fetch upstream
```

Now we create a new branch:

```sh
git checkout develop
git checkout -b feature/cool_thing upstream/develop
```

Reset this branch, now it will be an exact replica of upstream UPC/develop:

```sh
git reset --hard upstream/develop
git push --set-upstream origin feature/cool_thing
```

Now work on your code, test it so it is great. Then commit, push and create a *pull request*.
