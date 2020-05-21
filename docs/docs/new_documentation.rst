New documentation
=================


We build documentation and host it in `Read the Docs`_.

.. _Read the Docs: http://readthedocs.org/
.. _reStructuredText: http://docutils.sourceforge.net/rst.html

All documentation files are stored only in ``gh-pages`` branch, with the following directory structure::

    docs
    ├── _config.yml
    ├── devel-docs
    ├── docs
    └── index.rst

Documentation is created using `reStructuredText`_ , is an easy-to-read, what-you-see-is-what-you-get plaintext markup syntax and parser system.

Procedure
---------

    1. Consider the editing style of existing pages. 
    2. Edit a doc page or create a new one in ``gh-pages`` branch.
    3. Insert in ``index.rst`` according to the section.

.. note:: Documentation web is updated automatically, thanks to `Read the Docs`_.


Sidebar
-------

The organization of the sidebar is configured in the ``index.rst``. If you create a new documentation page remember to include in the section more according to the content. 
Add the ``directory`` and the name of ``rst file``, e.g.: 

    ``new_documentation.rst`` in ``docs/`` will be ``docs/new_documentation`` somewhere in the ``index.rst``

Convert POD files
-----------------

Install ``libpod-pom-view-restructured-perl`` in your computer.


Step-by-step contributing to docs
---------------------------------

So you want to contribute a documentation fix or new entry. Follow these 10 steps
carefully.

1. Create a git account at `GitHub.com`_ if you don't already have one.
2. Go to the `Ravada github repository`_.
3. Create your own project copy clicking the ``fork`` button at the top right of the page
4. Configure your git account in your PC::

    git config --global user.email "user@domain.com"
    git config --global user.name "Your real name"

4. Download your copy ``git clone https://github.com/YOUR_GITHUB_ACCOUNT/ravada``
5. Change to the github pages branch: ``cd ravada ; git checkout gh-pages``
6. Edit the file inside the ``docs/docs/`` directory
7. If it is a new file run ``git add new_file.rst``
8. Commit changes. It will ask for a one line description: ``git commit -a``
9. Send the changes to github: ``git push``
10. Go to `GitHub.com`_ and do a ``Pull Request``. Make sure it is from the gh-pages branch

.. image:: ../../img/pr_gh_pages.jpg

.. _Github.com: http://github.com/
.. _Ravada github repository: https://github.com/UPC/ravada
