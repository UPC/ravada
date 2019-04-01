// These tables map the js keyboard keys to the spice equivalent
wdi.KeymapPTBR = function() {

	// regular keys with associated chars. The columns  means all the event flux to activate the key (i.e. [key up, key down])
	// all the js events associated to these keys should have a charKey associated
	var charmapPTBR = {};

	// primeira fileira
    	charmapPTBR['\'']  = [[0x29, 0, 0, 0], [0xA9, 0, 0, 0]];
    	charmapPTBR['"']   = [[0x2A, 0, 0, 0], [0x29, 0, 0, 0], [0xA9, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['1']   = [[0x2, 0, 0, 0], [0x82, 0, 0, 0]];
	charmapPTBR['!']   = [[0x2A, 0, 0, 0], [0x2, 0, 0, 0], [0x82, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['¹']   = [[0xE0, 0x38, 0, 0], [0x2, 0, 0, 0], [0x82, 0, 0, 0], [0xE0, 0xB8, 0, 0]];
	charmapPTBR['2']   = [[0x3, 0, 0, 0], [0x83, 0, 0, 0]];
	charmapPTBR['@']   = [[0x2A, 0, 0, 0], [0x3, 0, 0, 0], [0x83, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['²']   = [[0xE0, 0x38, 0, 0], [0x3, 0, 0, 0], [0x83, 0, 0, 0], [0xE0, 0xB8, 0, 0]];
	charmapPTBR['3']   = [[0x4, 0, 0, 0], [0x84, 0, 0, 0]];
	charmapPTBR['#']   = [[0x2A, 0, 0, 0], [0x4, 0, 0, 0], [0x84, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['³']   = [[0xE0, 0x38, 0, 0], [0x4, 0, 0, 0], [0x84, 0, 0, 0], [0xE0, 0xB8, 0, 0]];
	charmapPTBR['4']   = [[0x5, 0, 0, 0], [0x85, 0, 0, 0]];
	charmapPTBR['$']   = [[0x2A, 0, 0, 0], [0x5, 0, 0, 0], [0x85, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['£']   = [[0xE0, 0x38, 0, 0], [0x5, 0, 0, 0], [0x85, 0, 0, 0], [0xE0, 0xB8, 0, 0]];
	charmapPTBR['5']   = [[0x6, 0, 0, 0], [0x86, 0, 0, 0]];
	charmapPTBR['%']   = [[0x2A, 0, 0, 0], [0x6, 0, 0, 0], [0x86, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['¢']   = [[0xE0, 0x38, 0, 0], [0x6, 0, 0, 0], [0x86, 0, 0, 0], [0xE0, 0xB8, 0, 0]];
	charmapPTBR['6']   = [[0x7, 0, 0, 0], [0x87, 0, 0, 0]];
	charmapPTBR['¨']   = [[0x2A, 0, 0, 0], [0x7, 0, 0, 0], [0x87, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['¬']   = [[0xE0, 0x38, 0, 0], [0x7, 0, 0, 0], [0x87, 0, 0, 0], [0xE0, 0xB8, 0, 0]];
	charmapPTBR['7']   = [[0x8, 0, 0, 0], [0x88, 0, 0, 0]];
	charmapPTBR['&']   = [[0x2A, 0, 0, 0], [0x8, 0, 0, 0], [0x88, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['8']   = [[0x9, 0, 0, 0], [0x89, 0, 0, 0]];
	charmapPTBR['*']   = [[0x2A, 0, 0, 0], [0x9, 0, 0, 0], [0x89, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['(']   = [[0x2A, 0, 0, 0], [0x0A, 0, 0, 0], [0x8A, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['9']   = [[0x0A, 0, 0, 0], [0x8A, 0, 0, 0]];
	charmapPTBR[')']   = [[0x2A, 0, 0, 0], [0x0B, 0, 0, 0], [0x8B, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['0']   = [[0x0B, 0, 0, 0], [0x8B, 0, 0, 0]];
	charmapPTBR['-']   = [[0x0C, 0, 0, 0], [0x8C, 0, 0, 0]];
	charmapPTBR['_']   = [[0x2A, 0, 0, 0], [0x0C, 0, 0, 0], [0x8C, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['+']   = [[0x1B, 0, 0, 0], [0x9B, 0, 0, 0]];
	charmapPTBR['=']   = [[0x2A, 0, 0, 0], [0x0B, 0, 0, 0], [0x8B, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['§']   = [[0xE0, 0x38, 0, 0], [0x0B, 0, 0, 0], [0x8B, 0, 0, 0], [0xE0, 0xB8, 0, 0]];

	// segunda fileira
	charmapPTBR['q']   = [[0x10, 0, 0, 0], [0x90, 0, 0, 0]];
	charmapPTBR['Q']   = [[0x2A, 0, 0, 0], [0x10, 0, 0, 0], [0x90, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['w']   = [[0x11, 0, 0, 0], [0x91, 0, 0, 0]];
	charmapPTBR['W']   = [[0x2A, 0, 0, 0], [0x11, 0, 0, 0], [0x91, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['e']   = [[0x12, 0, 0, 0], [0x92, 0, 0, 0]];
	charmapPTBR['E']   = [[0x2A, 0, 0, 0], [0x12, 0, 0, 0], [0x92, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['r']   = [[0x13, 0, 0, 0], [0x93, 0, 0, 0]];
	charmapPTBR['R']   = [[0x2A, 0, 0, 0], [0x13, 0, 0, 0], [0x93, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['t']   = [[0x14, 0, 0, 0], [0x94, 0, 0, 0]];
	charmapPTBR['T']   = [[0x2A, 0, 0, 0], [0x14, 0, 0, 0], [0x94, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['y']   = [[0x15, 0, 0, 0], [0x95, 0, 0, 0]];
	charmapPTBR['Y']   = [[0x2A, 0, 0, 0], [0x15, 0, 0, 0], [0x95, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['u']   = [[0x16, 0, 0, 0], [0x96, 0, 0, 0]];
	charmapPTBR['U']   = [[0x2A, 0, 0, 0], [0x16, 0, 0, 0], [0x96, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['i']   = [[0x17, 0, 0, 0], [0x97, 0, 0, 0]];
	charmapPTBR['I']   = [[0x2A, 0, 0, 0], [0x17, 0, 0, 0], [0x97, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['o']   = [[0x18, 0, 0, 0], [0x98, 0, 0, 0]];
	charmapPTBR['O']   = [[0x2A, 0, 0, 0], [0x18, 0, 0, 0], [0x98, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['p']   = [[0x19, 0, 0, 0], [0x99, 0, 0, 0]];
	charmapPTBR['P']   = [[0x2A, 0, 0, 0], [0x19, 0, 0, 0], [0x99, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['`']   = [[0x1A, 0, 0, 0], [0x9A, 0, 0, 0]];
	charmapPTBR['´']   = [[0x2A, 0, 0, 0], [0x1A, 0, 0, 0], [0x99, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['[']   = [[0x1B, 0, 0, 0], [0x9B, 0, 0, 0]];
	charmapPTBR['{']   = [[0x2A, 0, 0, 0], [0x1B, 0, 0, 0], [0x9B, 0, 0, 0], [0xAA, 0, 0, 0]];


	// terceira fileira
	charmapPTBR['a']   = [[0x1E, 0, 0, 0], [0x9E, 0, 0, 0]];
	charmapPTBR['A']   = [[0x2A, 0, 0, 0], [0x1E, 0, 0, 0], [0x9E, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['s']   = [[0x1F, 0, 0, 0], [0x9F, 0, 0, 0]];
	charmapPTBR['S']   = [[0x2A, 0, 0, 0], [0x1F, 0, 0, 0], [0x9F, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['d']   = [[0x20, 0, 0, 0], [0xA0, 0, 0, 0]];
	charmapPTBR['D']   = [[0x2A, 0, 0, 0], [0x20, 0, 0, 0], [0xA0, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['f']   = [[0x21, 0, 0, 0], [0xA1, 0, 0, 0]];
	charmapPTBR['F']   = [[0x2A, 0, 0, 0], [0x21, 0, 0, 0], [0xA1, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['g']   = [[0x22, 0, 0, 0], [0xA2, 0, 0, 0]];
	charmapPTBR['G']   = [[0x2A, 0, 0, 0], [0x22, 0, 0, 0], [0xA2, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['h']   = [[0x23, 0, 0, 0], [0xA3, 0, 0, 0]];
	charmapPTBR['H']   = [[0x2A, 0, 0, 0], [0x23, 0, 0, 0], [0xA3, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['j']   = [[0x24, 0, 0, 0], [0xA4, 0, 0, 0]];
	charmapPTBR['J']   = [[0x2A, 0, 0, 0], [0x24, 0, 0, 0], [0xA4, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['k']   = [[0x25, 0, 0, 0], [0xA5, 0, 0, 0]];
	charmapPTBR['K']   = [[0x2A, 0, 0, 0], [0x25, 0, 0, 0], [0xA5, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['l']   = [[0x26, 0, 0, 0], [0xA6, 0, 0, 0]];
	charmapPTBR['L']   = [[0x2A, 0, 0, 0], [0x26, 0, 0, 0], [0xA6, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['ç']   = [[0x0D, 0, 0, 0], [0x8D, 0, 0, 0]];
	charmapPTBR['Ç']   = [[0x2A, 0, 0, 0], [0x0D, 0, 0, 0], [0x8D, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['^']   = [[0x2A, 0, 0, 0], [0x28, 0, 0, 0], [0xA8, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['~']   = [[0x28, 0, 0, 0], [0xA8, 0, 0, 0]];
	charmapPTBR['ª']   = [[0xE0, 0x38, 0, 0], [0x28, 0, 0, 0], [0xA8, 0, 0, 0], [0xE0, 0xB8, 0, 0]];
	charmapPTBR[']']   = [[0x2B, 0, 0, 0], [0xAB, 0, 0, 0]];
	charmapPTBR['}']   = [[0x2A, 0, 0, 0], [0x2B, 0, 0, 0], [0xAB, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['º']   = [[0xE0, 0x38, 0, 0], [0x2B, 0, 0, 0], [0xAB, 0, 0, 0], [0xE0, 0xB8, 0, 0]];


	// quarta fileira
    	charmapPTBR['\\']   = [[0x2B, 0, 0, 0], [0xAB, 0, 0, 0]];
    	charmapPTBR['|']   = [[0x2A, 0, 0, 0], [0x2B, 0, 0, 0], [0xAB, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['z']   = [[0x2C, 0, 0, 0], [0xAC, 0, 0, 0]];
	charmapPTBR['Z']   = [[0x2A, 0, 0, 0], [0x2C, 0, 0, 0], [0xAC, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['x']   = [[0x2D, 0, 0, 0], [0xAD, 0, 0, 0]];
	charmapPTBR['X']   = [[0x2A, 0, 0, 0], [0x2D, 0, 0, 0], [0xAD, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['c']   = [[0x2E, 0, 0, 0], [0xAE, 0, 0, 0]];
	charmapPTBR['C']   = [[0x2A, 0, 0, 0], [0x2E, 0, 0, 0], [0xAE, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['v']   = [[0x2F, 0, 0, 0], [0xAF, 0, 0, 0]];
	charmapPTBR['V']   = [[0x2A, 0, 0, 0], [0x2F, 0, 0, 0], [0xAF, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['b']   = [[0x30, 0, 0, 0], [0xB0, 0, 0, 0]];
	charmapPTBR['B']   = [[0x2A, 0, 0, 0], [0x30, 0, 0, 0], [0xB0, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['n']   = [[0x31, 0, 0, 0], [0xB1, 0, 0, 0]];
	charmapPTBR['N']   = [[0x2A, 0, 0, 0], [0x31, 0, 0, 0], [0xB1, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['m']   = [[0x32, 0, 0, 0], [0xB2, 0, 0, 0]];
	charmapPTBR['M']   = [[0x2A, 0, 0, 0], [0x32, 0, 0, 0], [0xB2, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR[',']   = [[0x33, 0, 0, 0], [0xB3, 0, 0, 0]];
	charmapPTBR['<']   = [[0x2A, 0, 0, 0], [0x33, 0, 0, 0], [0xB3, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['.']   = [[0x34, 0, 0, 0], [0xB4, 0, 0, 0]];
	charmapPTBR['>']   = [[0x2A, 0, 0, 0], [0x34, 0, 0, 0], [0xB4, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR[';']   = [[0x2A, 0, 0, 0], [0x33, 0, 0, 0], [0xB3, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR[':']   = [[0x2A, 0, 0, 0], [0x34, 0, 0, 0], [0xB4, 0, 0, 0], [0xAA, 0, 0, 0]];

	charmapPTBR['?']   = [[0x2A, 0, 0, 0], [0x0C, 0, 0, 0], [0x8C, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['/']   = [[0x2A, 0, 0, 0], [0x8, 0, 0, 0], [0x88, 0, 0, 0], [0xAA, 0, 0, 0]];
	charmapPTBR['°']   = [[0xE0, 0x38, 0, 0], [0x62, 0, 0, 0], [0xE2, 0, 0, 0], [0xE0, 0xB8, 0, 0]];

	// quinta fileira
	charmapPTBR[' ']   = [[0x39, 0, 0, 0], [0xB9, 0, 0, 0]];


	// keyboard keys without character associated.
	// all the js events associated to these keys should have a keyChar associated
	var keymapPTBR = [];

	keymapPTBR[27]                 = 0x1; // ESC
	keymapPTBR[9]                 = 0x0F; // TAB
	//keymapPTBR[20]                = 0x3A; // BLOQ.MAY. => see the charmap, all the capital letters and shift chars send a shift in their sequence
	keymapPTBR[16]                = 0x2A; // LEFT SHIFT and RIGHT SHIFT
	keymapPTBR[91]                = 0x5B; // LEFT GUI (META, COMMAND) 
	keymapPTBR[93]                = 0x38; // MENU 
	keymapPTBR[17]                = 0x1D; // LEFT CONTROL and RIGHT CONTROL
	keymapPTBR[32]                = 0x39; // SPACE => see the charmap
	keymapPTBR[8]                 = 0x0E; // BACKSPACE
	keymapPTBR[13]                = 0x1C; // ENTER
	keymapPTBR[225]               = 0x5D; // RIGHT ALT (ALT GR) => see the charmap, all the altgr chars send a altgr in their sequence
	keymapPTBR[18]                = 0x38; // LEFT ALT
	keymapPTBR[92]                = 0x5C; // RIGHT GUI (WINDOWS)
	keymapPTBR[38]                = 0x48; // UP ARROW
	keymapPTBR[37]                = 0x4B; // LEFT ARROW
	keymapPTBR[40]                = 0x50; // DOWN ARROW
	keymapPTBR[39]                = 0x4D; // RIGHT ARROW
	keymapPTBR[45]                = 0x52; // INSERT
	keymapPTBR[46]                = 0x53; // DELETE
	keymapPTBR[36]                = 0x47; // HOME
	keymapPTBR[35]                = 0x4F; // FIN
	keymapPTBR[33]                = 0x49; // PAGE UP
	keymapPTBR[34]                = 0x51; // PAGE UP
	keymapPTBR[144]               = 0x45; // BLOQ.NUM.
	keymapPTBR[145]                = 0x46; // SCROLL LOCK
	keymapPTBR[112]                = 0x3B; // F1
	keymapPTBR[113]                = 0x3C; // F2
	keymapPTBR[114]                = 0x3D; // F3
	keymapPTBR[115]                = 0x3E; // F4
	keymapPTBR[116]                = 0x3F; // F5
	keymapPTBR[117]                = 0x40; // F6
	keymapPTBR[118]                = 0x41; // F7
	keymapPTBR[119]                = 0x42; // F8
	keymapPTBR[120]                = 0x43; // F9
	keymapPTBR[121]                = 0x44; // F10
	keymapPTBR[122]                = 0x57; // F11
	keymapPTBR[123]                = 0x58; // F12

	keymapPTBR[106]                 = 0x37; // KP_MULTIPLY
	keymapPTBR[109]                 = 0x4A; // KP_SUBTRACT
	keymapPTBR[107]                 = 0x4E; // KP_ADD

	keymapPTBR[189]                = 0x0C; // OEM_MINUS
	keymapPTBR[187]                = 0x0D; // OEM_PLUS
	keymapPTBR[219]                = 0x1A; // OEM_4 (grave and acute)
	keymapPTBR[221]                = 0x1B; // OEM_6 ({ and [)
	keymapPTBR[186]                = 0x27; // OEM_1 (c-cedilla)
	keymapPTBR[222]                = 0x28; // OEM_7 (^~)
	keymapPTBR[220]                = 0x2B; // OEM_5 (}])
	keymapPTBR[192]                = 0x29; // OEM_3 (' ")
	keymapPTBR[188]                = 0x33; // OEM_COMMA (< ,)
	keymapPTBR[190]                = 0x34; // OEM_PERIOD (> .)

	// went thru hell to find the correct codes for these! -- see the docs at http://www.quadibloc.com/comp/scan.htm, referenced as "INT 1" and "INT 3) (grr...)
	keymapPTBR[220]                = 0x56; // backslash and pipe
	keymapPTBR[191]                = 0x73; // slash and interrogation mark
	keymapPTBR[111]                	= 0x73; // KP_DIVIDE -- this won't work at all. Remapped to INT 3.

	// combination keys with ctrl
	var ctrlKeymapPTBR = [];

	ctrlKeymapPTBR[65]                = 0x1E; // a
	ctrlKeymapPTBR[81]                = 0x10; // q
	ctrlKeymapPTBR[87]                = 0x11; // w
	ctrlKeymapPTBR[69]                = 0x12; // e
	ctrlKeymapPTBR[82]                = 0x13; // r
	ctrlKeymapPTBR[84]                = 0x14; // t
	ctrlKeymapPTBR[89]                = 0x15; // y
	ctrlKeymapPTBR[85]                = 0x16; // u
	ctrlKeymapPTBR[73]                = 0x17; // i
	ctrlKeymapPTBR[79]                = 0x18; // o
	ctrlKeymapPTBR[80]                = 0x19; // p
	ctrlKeymapPTBR[65]                = 0x1E; // a
	ctrlKeymapPTBR[83]                = 0x1F; // s
	ctrlKeymapPTBR[68]                = 0x20; // d
	ctrlKeymapPTBR[70]                = 0x21; // f
	ctrlKeymapPTBR[71]                = 0x22; // g
	ctrlKeymapPTBR[72]                = 0x23; // h
	ctrlKeymapPTBR[74]                = 0x24; // j
	ctrlKeymapPTBR[75]                = 0x25; // k
	ctrlKeymapPTBR[76]                = 0x26; // l
	ctrlKeymapPTBR[90]                = 0x2C; // z
	ctrlKeymapPTBR[88]                = 0x2D; // x
	ctrlKeymapPTBR[67]                = 0x2E; // c
	//ctrlKeymapPTBR[86]                = 0x2F; // v      to enable set disableClipboard = true in run.js
	ctrlKeymapPTBR[66]                = 0x30; // b
	ctrlKeymapPTBR[78]                = 0x31; // n
	ctrlKeymapPTBR[77]                = 0x32; // m

	// reserved ctrl+? combinations we want to intercept from browser and inject manually to spice
	var reservedCtrlKeymap = [];
	reservedCtrlKeymap[86] = 0x2F;

	return {
		getKeymap: function() {
			return keymapPTBR;
		},

		getCtrlKeymap: function() {
			return ctrlKeymapPTBR;
		},

		getReservedCtrlKeymap: function() {
			return reservedCtrlKeymap;
		},

		getCharmap: function() {
			return charmapPTBR;
		},

		setCtrlKey: function (key, val) {
			ctrlKeymapPTBR[key] = val;
		}
	};
}( );
