
var sendKey=function(type,n){
	var obj={
		'generated': true,
		'type': type,
		'keyCode': n,
		'charCode': 0
	};
	//inputProcess object,window.inputProcess=
	//in application.js init， window.inputProcess=this.inputProcess;
	app.inputProcess.send([type,[obj]], type);
}

var sendCtrlAltDel=function(){
	app.disableKeyboard();
	app.sendShortcut("CtrlAltDel");
	app.enableKeyboard();
}


var switchVT=function(keynum){
	var base=111;

	app.disableKeyboard();
	sendKey("keydown",17);
	sendKey("keydown",18);
	sendKey("keydown",base+keynum);
	sendKey("keyup",base+keynum);
	sendKey("keyup",18);
	sendKey("keyup",17);
	app.enableKeyboard();
}

var switchKB=function(layout){
	wdi.Keymap.loadKeyMap("us");
	wdi.Keymap.loadKeyMap(layout);
	alert("mapa de teclado " +  layout + " carregado.");
}

