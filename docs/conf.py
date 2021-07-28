extensions = [
    'sphinx-prompt'
]

# The suffix(es) of source filenames.
# You can specify multiple suffix as a list of string:
# source_suffix = ['.rst', '.md']
source_suffix = '.rst'

# The encoding of source files.
#source_encoding = 'utf-8-sig'

# The master toctree document.
master_doc = 'index'

# General information about the project.
project = u'RavadaVDI'
copyright = u'2018-2021, RavadaVDI'
author = u'Ravada Team'

# Language to be used for generating the HTML full-text search index.
# Sphinx supports the following languages:
#   'da', 'de', 'en', 'es', 'fi', 'fr', 'hu', 'it', 'ja'
#   'nl', 'no', 'pt', 'ro', 'ru', 'sv', 'tr'
html_search_language = 'en'

# Theme options
html_theme_options = {
    'logo_only': True,  # if we have a html_logo below, this shows /only/ the logo with no title text
    'collapse_navigation': False,  # Collapse navigation (False makes it tree-like)
}
html_static_path = []

html_logo = 'docs/../../img/logo_ravada.png'

# Couldn't find a way to retrieve variables nor do advanced string
# concat from reST, so had to hardcode this in the "epilog" added to
# all pages. This is used in index.rst to display the Weblate badge.
# On English pages, the badge points to the language-neutral engage page.
rst_epilog = """
.. |weblate_widget| image:: https://hosted.weblate.org/widgets/ravada/-/287x66-white.png
    :alt: Translation status
    :target: https://hosted.weblate.org/engage/ravada/
    :width: 287
    :height: 66
.. |weblate2_widget| image:: https://hosted.weblate.org/widgets/ravada/-/multi-auto.svg
    :alt: Translation status
    :target: https://hosted.weblate.org/engage/ravada/
    :width: 400
    :height: 285
""".format()
