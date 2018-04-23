function startIntro(){
    var intro = introJs();
        intro.setOptions({
          steps: [
            {
              intro: "<center><h4><b>Welcome to Ravada Virtual Desktop</b></h4><h5>Your personal virtual machines in one place.</h5>" +
              "<h4>Get the SPICE client</h4>" +
              "<a target=_blank href=\"https://virt-manager.org/download/\"><i class=\"fab fa-linux fa-3x\" aria-hidden=\"true\"></i></a>&nbsp;" +
              "<a target=_blank href=\"https://virt-manager.org/download/\"><i class=\"fab fa-windows fa-3x\" aria-hidden=\"true\"></i></a>&nbsp;</center>"
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
              intro: "<center><h5>There's more information in the <a target=_blank href=\"http://ravada.readthedocs.io/\">documentation</a> and on our <a target=_blank href=\"https://ravada.upc.edu\">website</a>.</h5>" +
              "<h6>If you like Ravada VDI drop us a <a href=\"mailto:ravada@telecos.upc.edu\">line</a>," +
              "<a class=\"twitter-share-button\" href=\"https://twitter.com/intent/tweet?text=Hi,%20I'm%20using%20@ravada_vdi\">" +
              "tweet</a>, <a href=\"http://t.me/ravadavdi\">telegram</a> or <a href=\"https://github.com/UPC/ravada\">star</a> in github.</h6></center>"
            }
          ],
          showProgress: true,
          showBullets: false,
        });
    var doneTour = localStorage.getItem('EventTour') === 'Completed';
        if (doneTour) {
            return;
        }
        else {
            intro.start()
            intro.oncomplete(function () {
                localStorage.setItem('EventTour', 'Completed');
            });
            intro.onexit(function () {
                localStorage.setItem('EventTour', 'Completed');
            });
        }
}
