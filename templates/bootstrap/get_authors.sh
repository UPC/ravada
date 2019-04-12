#!/bin/bash
echo "<ul>" > authors.html.ep
git log --format='%aN' | grep ' ' | sort -u | perl -ne 'chomp ; print "<li>$_</li>\n"' >> authors.html.ep
echo "</ul>" >> authors.html.ep
echo "<%=l 'Thanks to:' %>" >> authors.html.ep
echo "<ul>
<li>Francesc Oller</li>
<li>Jorge Mata</li>
</ul>" >> authors.html.ep
