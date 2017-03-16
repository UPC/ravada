# Change Log


**Implemented enhancements:**

- Remove base [\#12]
- New machine parameters [\#8]
- make ping localhost packend faster and lighter [\#66]
- Add a form to rename a virtual machine [\#78]
- Rename domains [\#41]
- Spin off bases from clones [\#67]
- Message to the user when downloading ISO [\#77]
- Name (copy) the cloned domains [\#92]
- Requests for the same domain should queue [\#93]
- Rename domains [\#41]
- Log out the user after starting a new machine [\#79]
- Hide and publish bases [\#86]
- Let the users shutdown their machines from the web [\#98]
- Add iptables rules for the domains [\#51]
- Release information in about page [\#62]
- Disable prepare base button for domains with clones [\#89]
- Start a machine must be prioritary [\#97]

**Fixed bugs:**

- Remove file base entries when removing domain [\#80]
- Remove base button does nothing [\#72]
- Attempted double use of PCI Address [\#71]
- At /machines there is a request for {{machine.id}}.png [\#68]
- Attempted double use of PCI Address [\#71]
- Domains won't start if host IP changes [\#84]
- Make clone volumes unique [\#87]
- Clones of clones crash at start with apparmor error DENIED [\#90]
- Prepare base doesn't send a message when done [\#91]
- Duplicate USB controllers with index 0 [\#99]
- Check USB redirection [\#101]
- The backend dies when mysql is down [\#102]
- message/read/"id".json calls doesnt mark message as read. [\#104]
- When user is logged and fails login form the frontend fails [\#73]
- When user gets logged out it gets access denied [\#76]
- two requests for start try to use open iptables [\#81]
- Skip tests when no VMs available [\#63]
- review KVM add volume [\#95]
- Test failed, prepare failed near "100": syntax error at User.pm [\#106]
