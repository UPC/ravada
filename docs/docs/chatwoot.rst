Live web Chatwoot
=================

If you want to offer a communication channel for users. We propose this simple and powerful solution.

`Chatwoot <https://chatwoot.com>`_ is live chat software. It's open source and has a great community. You can access the code `here <https://github.com/chatwoot/>`_.

You need a Chatwoot server, you have differents options. If you are interested in self-hosted follow this `guide <https://www.chatwoot.com/docs/deployment/architecture>`_.

Here you will not find a `chatwoot manual <https://www.chatwoot.com/docs/channels/website>`_, only a few steps to embed your widget code.

Once you have the widget you have to paste it in two files.

Available chat in login
-----------------------
Copy your widget before </body> tag at the end of ``/usr/share/ravada/templates/bootstrap/scripts.html.ep``

.. image:: images/chat_login.png

Available inside Ravada
-----------------------
Copy your widget before </body> tag at the end of ``/usr/share/ravada/templates/main/start.html.ep``

.. image:: images/chat_inside.png

If you have a custom login, then here: ``/usr/share/ravada/templates/main/custom/login_acme.html.ep``

And restart rvd_front service:

.. prompt:: bash #

    systemctl restart rvd_front
