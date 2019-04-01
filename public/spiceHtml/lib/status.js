

function getUrlVars() {
	var vars = {};
	var parts = window.location.href.replace(/[?&]+([^=&]+)=([^&]*)/gi, function(m,key,value) {
		vars[key] = value;
	});
	return vars;
}

function addDynamicContent() 
{
	// action buttons
	var tree = document.createDocumentFragment();
	var item1 = document.createElement("a");
	item1.setAttribute("id", "reset");
	item1.setAttribute("class", "btn btn-link");
	item1.setAttribute("href", "javascript:resetVM();");
	item1.appendChild(document.createTextNode("reset"));
	var item1glyph = document.createElement("span");
	item1glyph.setAttribute("class", "glyphicon glyphicon-repeat");

	var item2 = document.createElement("a");
	item2.setAttribute("id", "close");
	item2.setAttribute("class", "btn btn-link");
	item2.setAttribute("href", "javascript:window.close();");
	item2.appendChild(document.createTextNode("fechar"));
	var item2glyph = document.createElement("span");
	item2glyph.setAttribute("class", "glyphicon glyphicon-log-out");

	tree.appendChild(item1);
	tree.appendChild(item1glyph);
	tree.appendChild(item2);
	tree.appendChild(item2glyph);
	document.getElementById("action_toolbar").appendChild(tree);

	document.title = 'VM: ' + getUrlVars()["vm_name"] + ' (' + getUrlVars()["arch"] + '), IP: ' + getUrlVars()["ip_addr"];
}


function resetVM(vm_name) {

	$.get("/labvirtual/restartvm?name=" + getUrlVars()["vm_name"]);
	alert('Comando de reset enviado para VM ' + getUrlVars()["vm_name"] + ' com sucesso.');


}	
