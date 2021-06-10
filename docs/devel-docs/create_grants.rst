How to create a new grants
==========================

If you want to add a new grant, you have to do two things:

    -  Add the grant and enable it in to the BD
    -  Add the condition
    
You can see all the grants in the table 'grants_type', to add it automatically on start up the
backend you have to modify the functions ``_add_grants`` and ``_enable_grants`` in the file *lib/Ravada.pm*.

Now the test file is like this:

::
    
    ...
    
    sub _add_grants($self) {
    #   How to
    #   $self->_add_grant('grant_name', enable/disable by default, "description")

    #   Examples
        $self->_add_grant('shutdown', 1,"Can shutdown own virtual machines");
        $self->_add_grant('start_many',0,"Can have more than one machine started")
    }
    ...
    sub _enable_grants($self) {
    ...
    my @grants = (
        # How to
        # 'grant_name'
        
        # Examples
        'change_settings',  'change_settings_all',  'change_settings_clones'
        ,'clone',           'clone_all',            'create_base', 'create_machine'
        ,'grant'
        ,'manage_users'
        ,'remove',          'remove_all',   'remove_clone',     'remove_clone_all'
        ,'screenshot'
        ,'shutdown',        'shutdown_all',    'shutdown_clone'
        ,'screenshot'
        ,'start_many'
    );
    ...

Next for adding the conditions it depends of the situations but you may want to look into these files:

    -  "templates/main/settings_machine_tabs_head.html.ep" & "templates/main/settings_machine_tabs_head.html.ep" for Virtual Machine edit settings web page.
    -  "lib/Ravada/Auth/SQL.pm" all the grants conditions created (i.e. ``is_admin``, ``can_list_clones``, etc...).

**Note**: The functions like ``can_'grant_name'`` are not individually implemented. This function is automatically generated with the BD data. Its code is at *lib/Ravada/Auth/SQL.pm* ``sub AUTOLOAD``.

Grant user permissions by default
---------------------------------

At *lib/Ravada/Auth/SQL*, the sub *grant_user_permissions* sets the default for new
users. If the new permission should be for everybody, add it there too.


Defaults and upgrading
----------------------

*This sections requires some review, please contribute if you can*

Some permissions are granted by default to all the users. So when creating
a new grant you should check:

    - Old users are granted the new permissions
    - Newly created users get the permission too
    - Admin users get the permision, both old and new

Testing
-------

Some examples for testing can be found in */t/user/50_admin.t* and */t/user/40_grant_shutdown.t* also you may want to read the section **How to create tests**.
