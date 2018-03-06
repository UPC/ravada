function startIntro(){
        var intro = introJs();
          intro.setOptions({
            steps: [
              { 
                intro: "<h4>User guide step-to-step</h4><br /> " + 
                "<div class=\"alert alert-info\" ><small>You can use cursor keys & ESC for exit</small></div>"
              },
              { 
                intro: "Welcome to Ravada VDI"
              },
              {
                element: document.querySelector('#step1'),
                intro: "Available machines",
                position: 'right'
              },
              {
                element: document.querySelectorAll('#step2')[0],
                intro: "Start, stop and settings",
                position: 'right'
              },
              {
                element: '#step3',
                intro: 'More features, more fun.',
                position: 'left'
              },
              {
                element: '#step4',
                intro: "Another step.",
                position: 'bottom'
              },
              {
                element: '#step5',
                intro: 'The end'
              }
            ],
            showProgress: true,
            showBullets: false,
          });
          intro.start();
}
