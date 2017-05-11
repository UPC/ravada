
/* any user should be allowed these */
INSERT INTO grant_types(name,description) VALUES('clone',"can clone public virtual machines.");
INSERT INTO grant_types(name,description) VALUES('change_settings',"can change the settings of owned virtual machines.");
INSERT INTO grant_types(name,description) VALUES('remove',"can remove any virtual machines owned by the user.");
INSERT INTO grant_types(name,description) VALUES('screenshot',"can take a screenshot of any virtual machine owned by the user.");

/* managers should be allowed these */
INSERT INTO grant_types(name,description) VALUES('create_domain',"can create virtual machines.");
INSERT INTO grant_types(name,description) VALUES('create_base',"can create bases.");

/* managers should be allowed these */
INSERT INTO grant_types(name,description) VALUES('change_settings_clones',"can change the settings of any virtual machines cloned from one base owned by the user.");
INSERT INTO grant_types(name,description) VALUES('remove_clone',"can remove clones from virtual machines owned by the user.");
INSERT INTO grant_types(name,description) VALUES('shutdown_clone',"can shutdown clones from virtual machines owned by the user.");
INSERT INTO grant_types(name,description) VALUES('hibernate_clone',"can hibernate clones from virtual machines owned by the user.");

/* operators should be allowed these */
INSERT INTO grant_types(name,description) VALUES('change_settings_all',"can change the settings of any virtual machines.");
INSERT INTO grant_types(name,description) VALUES('remove_clone_all',"can remove any clone.");
INSERT INTO grant_types(name,description) VALUES('hibernate_clone_all',"can hibernate any clone.");

/* admins should be allowed these */
INSERT INTO grant_types(name,description) VALUES('clone_all',"can clone any virtual machine.");
INSERT INTO grant_types(name,description) VALUES('remove_all',"can remove any virtual machine.");
INSERT INTO grant_types(name,description) VALUES('shutdown_all',"can shutdown any virtual machine.");
INSERT INTO grant_types(name,description) VALUES('hibernate_all',"can hibernate any virtual machine.");
INSERT INTO grant_types(name,description) VALUES('screenshot_all',"can take a screenshot of any virtual machine.");

INSERT INTO grant_types(name,description) VALUES('grant','can grant permissions to other users');
INSERT INTO grant_types(name,description) VALUES('manage_users','can manage users.');
