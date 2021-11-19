Localization and translation
============================

.. centered:: |weblate2_widget|

You can translate Ravada at `Weblate <https://hosted.weblate.org/engage/ravada/>`__. As a feature rich computer aided translation tool, Weblate saves both developers and translators time.

.. centered:: |weblate_widget|

- Automated localization workflow
- Quality checks
- Attribution, all translator are properly credited

You can read weblate features in follow `link <https://hosted.weblate.org/projects/ravada/#languages>`_.

Ravada weblate repository is updated from Github, and the contributions goes automatic to develop branch in Github.

New entries
-----------

New english entries must be added in the ``en.po`` file. It's the origin of the other language files. This new strings will be incorporated automatically in weblate.

.. Warning:: Please don't add new entries in other .po files directly. Use `Weblate <https://hosted.weblate.org/projects/ravada/translation/>`__ instead.

The language files are stored `here <https://github.com/UPC/ravada/tree/master/lib/Ravada/I18N/>`_ in lib/Ravada/I18N.

When creating a new translation language, also add it in the frontend so it gets
listed for the end users. At around line 1337 in the ``sub _translation`` add
a line like this:

.. code-block:: perl

    sub _translations($c) {
        my %lang_name=(
            ar => 'Arab'
            ,en => 'English'
            ....
            ,XX => 'New language'

