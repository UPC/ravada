var messages = new Vue({
    el: '#messages'
    ,
    data: {
        alerts: []
    }
    ,methods: {
        close_alert: function(index) {
            var message = this.alerts.splice(index, 1);
            var toGet = '/messages/read/'+message[0].id+'.json';
            fetch(toGet);

        }
        ,subscribe: function(url) {
            console.log("subscribe alerts");
          var self = this;
          var ws = new WebSocket(url);
          ws.onopen = function(event) { ws.send('list_alerts') };
          ws.onclose = function() {
                ws = new WebSocket(url);
          };

          ws.onmessage = function(event) {
              var data = JSON.parse(event.data);
              for (var i=0;  i < data.length; i++) {
                  var message=data[i];
                  if (message.message == '' || !message.message ) {
                      message.message = message.subject;
                  }
                  self.$bvToast.toast(message.message, {
                      title: message.subject,
                      autoHideDelay: 15000,
                      appendToast:true
                  })
              }
          }

        }
    }
});
