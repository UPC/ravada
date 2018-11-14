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




