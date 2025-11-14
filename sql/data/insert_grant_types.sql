
/* any user should be allowed these */
INSERT INTO grant_types(name,description,enabled,default_user) VALUES('clone',"can clone public virtual machines.",1,1);
INSERT INTO grant_types(name,description,enabled,default_user) VALUES('change_settings',"can change the settings of owned virtual machines.",1,1);
INSERT INTO grant_types(name,description,enabled,default_user) VALUES('remove',"can remove any virtual machine owned by the user.",1,1);
INSERT INTO grant_types(name,description,enabled,default_user) VALUES('screenshot',"can take a screenshot of any virtual machine owned by the user.",1,1);

/* managers should be allowed these */
INSERT INTO grant_types(name,description) VALUES('create_machine',"can create virtual machines.");
INSERT INTO grant_types(name,description) VALUES('create_base',"can create bases.");

/* managers should be allowed these */
INSERT INTO grant_types(name,description) VALUES('change_settings_clones',"can change the settings of any virtual machine cloned from one base owned by the user.");
INSERT INTO grant_types(name,description) VALUES('remove_clone',"can remove clones from virtual machines owned by the user.");
INSERT INTO grant_types(name,description) VALUES('shutdown_clone',"can shutdown clones from virtual machines owned by the user.");
INSERT INTO grant_types(name,description) VALUES('hibernate_clone',"can hibernate clones from virtual machines owned by the user.");

/* operators should be allowed these */
INSERT INTO grant_types(name,description) VALUES('change_settings_all',"can change the settings of any virtual machine.");
INSERT INTO grant_types(name,description) VALUES('remove_clone_all',"can remove any clone.");
INSERT INTO grant_types(name,description) VALUES('hibernate_clone_all',"can hibernate any clone.");

/* Special users should be allowed these */
INSERT INTO grant_types(name,description, is_int, default_admin) VALUES('start_limit',"can have their own limit on started machines.", 1, 0); /* the value in grants_user will be the maximum number of concurrent machines instead of a boolean */

/* admins should be allowed these */
INSERT INTO grant_types(name,description) VALUES('clone_all',"can clone any virtual machine.");
INSERT INTO grant_types(name,description) VALUES('remove_all',"can remove any virtual machine.");
INSERT INTO grant_types(name,description) VALUES('shutdown_all',"can shutdown any virtual machine.");
INSERT INTO grant_types(name,description) VALUES('hibernate_all',"can hibernate any virtual machine.");
INSERT INTO grant_types(name,description) VALUES('screenshot_all',"can take a screenshot of any virtual machine.");

INSERT INTO grant_types(name,description, enabled,default_user) VALUES('grant','can grant permissions to other users', 1,0);
INSERT INTO grant_types(name,description) VALUES('manage_users','can manage users.');
