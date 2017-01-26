(function($){

    $.extend($.easing, {
        easeInOutCubic : function(x, t, b, c, d){
            if ((t/=d/2) < 1) return c/2*t*t*t + b;
            return c/2*((t-=2)*t*t + 2) + b;
        }
    });

    $.fn.outerFind = function(selector){
        return this.find(selector).addBack(selector);
    };

    (function($,sr){
        // debouncing function from John Hann
        // http://unscriptable.com/index.php/2009/03/20/debouncing-javascript-methods/
        var debounce = function (func, threshold, execAsap) {
            var timeout;

            return function debounced () {
                var obj = this, args = arguments;
                function delayed () {
                    if (!execAsap) func.apply(obj, args);
                    timeout = null;
                };

                if (timeout) clearTimeout(timeout);
                else if (execAsap) func.apply(obj, args);

                timeout = setTimeout(delayed, threshold || 100);
            };
        }
        // smartresize 
        jQuery.fn[sr] = function(fn){  return fn ? this.bind('resize', debounce(fn)) : this.trigger(sr); };

    })(jQuery,'smartresize');

    (function(){
        
        var scrollbarWidth = 0, originalMargin, touchHandler = function(event){
            event.preventDefault();
        };

        function getScrollbarWidth(){
            if (scrollbarWidth) return scrollbarWidth;
            var scrollDiv = document.createElement('div');
            $.each({
                top : '-9999px',
                width  : '50px',
                height : '50px',
                overflow : 'scroll', 
                position : 'absolute'
            }, function(property, value){
                scrollDiv.style[property] = value;
            });
            $('body').append(scrollDiv);
            scrollbarWidth = scrollDiv.offsetWidth - scrollDiv.clientWidth;
            $('body')[0].removeChild(scrollDiv);
            return scrollbarWidth;
        }

    })();

    $.isMobile = function(type){
        var reg = [];
        var any = {
            blackberry : 'BlackBerry',
            android : 'Android',
            windows : 'IEMobile',
            opera : 'Opera Mini',
            ios : 'iPhone|iPad|iPod'
        };
        type = 'undefined' == $.type(type) ? '*' : type.toLowerCase();
        if ('*' == type) reg = $.map(any, function(v){ return v; });
        else if (type in any) reg.push(any[type]);
        return !!(reg.length && navigator.userAgent.match(new RegExp(reg.join('|'), 'i')));
    };

    var isSupportViewportUnits = (function(){
        // modernizr implementation
        var $elem = $('<div style="height: 50vh; position: absolute; top: -1000px; left: -1000px;">').appendTo('body');
        var elem = $elem[0];
        var height = parseInt(window.innerHeight / 2, 10);
        var compStyle = parseInt((window.getComputedStyle ? getComputedStyle(elem, null) : elem.currentStyle)['height'], 10);
        $elem.remove();
        return compStyle == height;
    }());

    $(function(){

        $('html').addClass($.isMobile() ? 'mobile' : 'desktop');

        // .mbr-navbar--sticky
        $(window).scroll(function(){
            $('.mbr-navbar--sticky').each(function(){
                var method = $(window).scrollTop() > 10 ? 'addClass' : 'removeClass';
                $(this)[method]('mbr-navbar--stuck')
                    .not('.mbr-navbar--open')[method]('mbr-navbar--short');
            });
        });

        // .mbr-hamburger
        $(document).on('add.cards change.cards', function(event){
            $(event.target).outerFind('.mbr-hamburger:not(.mbr-added)').each(function(){
                $(this).addClass('mbr-added')
                    .click(function(){
                        $(this)
                            .toggleClass('mbr-hamburger--open')
                            .parents('.mbr-navbar')
                            .toggleClass('mbr-navbar--open')
                            .removeClass('mbr-navbar--short');
                    }).parents('.mbr-navbar').find('a:not(.mbr-hamburger)').click(function(){
                        $('.mbr-hamburger--open').click();
                    });
            });
        });
        $(window).smartresize(function(){
            if ($(window).width() > 991)
                $('.mbr-navbar--auto-collapse .mbr-hamburger--open').click();
        }).keydown(function(event){
            if (27 == event.which) // ESC
                $('.mbr-hamburger--open').click();
        });

        if ($.isMobile() && navigator.userAgent.match(/Chrome/i)){ // simple fix for Chrome's scrolling
            (function(width, height){
                var deviceSize = [width, width];
                deviceSize[height > width ? 0 : 1] = height;
                $(window).smartresize(function(){
                    var windowHeight = $(window).height();
                    if ($.inArray(windowHeight, deviceSize) < 0)
                        windowHeight = deviceSize[ $(window).width() > windowHeight ? 1 : 0 ];
                    $('.mbr-section--full-height').css('height', windowHeight + 'px');
                });
            })($(window).width(), $(window).height());
        } else if (!isSupportViewportUnits){ // fallback for .mbr-section--full-height
            $(window).smartresize(function(){
                $('.mbr-section--full-height').css('height', $(window).height() + 'px');
            });
            $(document).on('add.cards', function(event){
                if ($('html').hasClass('mbr-site-loaded') && $(event.target).outerFind('.mbr-section--full-height').length)
                    $(window).resize();
            });
        }

        // .mbr-section--16by9 (16 by 9 blocks autoheight)
        function calculate16by9(){
            $(this).css('height', $(this).parent().width() * 9 / 16);
        }
        $(window).smartresize(function(){
            $('.mbr-section--16by9').each(calculate16by9);
        });
        $(document).on('add.cards change.cards', function(event){
            var enabled = $(event.target).outerFind('.mbr-section--16by9');
            if (enabled.length){
                enabled
                    .attr('data-16by9', 'true')
                    .each(calculate16by9);
            } else {
                $(event.target).outerFind('[data-16by9]')
                    .css('height', '')
                    .removeAttr('data-16by9');
            }
        });


        // .mbr-parallax-background
        if ($.fn.jarallax && !$.isMobile()){
            $(document).on('destroy.parallax', function(event){
                $(event.target).outerFind('.mbr-parallax-background')
                    .jarallax('destroy')
                    .css('position', '');
            });
            $(document).on('add.cards change.cards', function(event){
                $(event.target).outerFind('.mbr-parallax-background')
                    .jarallax()
                    .css('position', 'relative');
            });
        }

        // .mbr-social-likes
        if ($.fn.socialLikes){
            $(document).on('add.cards', function(event){
                $(event.target).outerFind('.mbr-social-likes:not(.mbr-added)').on('counter.social-likes', function(event, service, counter){
                    if (counter > 999) $('.social-likes__counter', event.target).html(Math.floor(counter / 1000) + 'k');
                }).socialLikes({initHtml : false});
            });
        }

        // .mbr-fixed-top
        var fixedTopTimeout, scrollTimeout, prevScrollTop = 0, fixedTop = null, isDesktop = !$.isMobile();
        $(window).scroll(function(){
            if (scrollTimeout) clearTimeout(scrollTimeout);
            var scrollTop = $(window).scrollTop();
            var scrollUp  = scrollTop <= prevScrollTop || isDesktop;
            prevScrollTop = scrollTop;
            if (fixedTop){
                var fixed = scrollTop > fixedTop.breakPoint;
                if (scrollUp){
                    if (fixed != fixedTop.fixed){
                        if (isDesktop){
                            fixedTop.fixed = fixed;
                            $(fixedTop.elm).toggleClass('is-fixed');
                        } else {
                            scrollTimeout = setTimeout(function(){
                                fixedTop.fixed = fixed;
                                $(fixedTop.elm).toggleClass('is-fixed');
                            }, 40);
                        }
                    }
                } else {
                    fixedTop.fixed = false;
                    $(fixedTop.elm).removeClass('is-fixed');
                }
            }
        });
        $(document).on('add.cards delete.cards', function(event){
            if (fixedTopTimeout) clearTimeout(fixedTopTimeout);
            fixedTopTimeout = setTimeout(function(){
                if (fixedTop){
                    fixedTop.fixed = false;
                    $(fixedTop.elm).removeClass('is-fixed');
                }
                $('.mbr-fixed-top:first').each(function(){
                    fixedTop = {
                        breakPoint : $(this).offset().top + $(this).height() * 3,
                        fixed : false,
                        elm : this
                    };
                    $(window).scroll();
                });
            }, 650);
        });

        // .mbr-google-map
        var loadGoogleMap = function(){
            var $this = $(this), markers = [], coord = function(pos){
                return new google.maps.LatLng(pos[0], pos[1]);
            };
            var params = $.extend({
                zoom       : 14,
                type       : 'ROADMAP',
                center     : null,
                markerIcon : null,
                showInfo   : true
            }, eval('(' + ($this.data('google-map-params') || '{}') + ')'));
            $this.find('.mbr-google-map__marker').each(function(){
                var coord = $(this).data('coordinates');
                if (coord){
                    markers.push({
                        coord    : coord.split(/\s*,\s*/),
                        icon     : $(this).data('icon') || params.markerIcon,
                        content  : $(this).html(),
                        template : $(this).html('{{content}}').removeAttr('data-coordinates data-icon')[0].outerHTML
                    });
                }
            }).end().html('').addClass('mbr-google-map--loaded');
            if (markers.length){
                var map = this.Map = new google.maps.Map(this, {
                    scrollwheel : false,
                    // prevent draggable on mobile devices
                    draggable   : !$.isMobile(),
                    zoom        : params.zoom,
                    mapTypeId   : google.maps.MapTypeId[params.type],
                    center      : coord(params.center || markers[0].coord)
                });
                $(window).smartresize(function(){
                   var center = map.getCenter();
                   google.maps.event.trigger(map, 'resize');
                   map.setCenter(center); 
                });
                map.Geocoder = new google.maps.Geocoder;
                map.Markers = [];
                $.each(markers, function(i, item){
                    var marker = new google.maps.Marker({
                        map       : map,
                        position  : coord(item.coord),
                        icon      : item.icon,
                        animation : google.maps.Animation.DROP
                    });
                    var info = marker.InfoWindow = new google.maps.InfoWindow();
                    info._setContent = info.setContent;
                    info.setContent = function(content){
                        return this._setContent(content ? item.template.replace('{{content}}', content) : '');
                    };
                    info.setContent(item.content);
                    google.maps.event.addListener(marker, 'click', function(){
                        if (info.anchor && info.anchor.visible) info.close();
                        else if (info.getContent()) info.open(map, marker);
                    });
                    if (item.content && params.showInfo){
                        google.maps.event.addListenerOnce(marker, 'animation_changed', function(){
                            setTimeout(function(){
                                info.open(map, marker);
                            }, 350);
                        });
                    }
                    map.Markers.push(marker);
                });
            }
        };
        $(document).on('add.cards', function(event){
            if (window.google && google.maps){
                $(event.target).outerFind('.mbr-google-map').each(function(){
                    loadGoogleMap.call(this);
                });
            }
        });

        // embedded videos
        $(window).smartresize(function(){
            $('.mbr-embedded-video').each(function(){
                $(this).height(
                    $(this).width() *
                    parseInt($(this).attr('height') || 315) /
                    parseInt($(this).attr('width') || 560)
                );
            });
        });
        $(document).on('add.cards', function(event){
            if ($('html').hasClass('mbr-site-loaded') && $(event.target).outerFind('iframe').length)
                $(window).resize();
        });

        $(document).on('add.cards', function(event){
            $(event.target).outerFind('[data-bg-video]').each(function(){
                var result, videoURL = $(this).data('bg-video'), patterns = [
                    /\?v=([^&]+)/,
                    /(?:embed|\.be)\/([-a-z0-9_]+)/i,
                    /^([-a-z0-9_]+)$/i
                ];
                for (var i = 0; i < patterns.length; i++){
                    if (result = patterns[i].exec(videoURL)){
                        var previewURL = 'http' + ('https:' == location.protocol ? 's' : '') + ':';
                        previewURL += '//img.youtube.com/vi/' + result[1] + '/maxresdefault.jpg';

                        var $img = $('<div class="mbr-background-video-preview">')
                            .hide()
                            .css({
                                backgroundSize: 'cover',
                                backgroundPosition: 'center'
                            })
                        $('.container:eq(0)', this).before($img);

                        $('<img>').on('load', function() {
                            if (120 == (this.naturalWidth || this.width)) {
                                // selection of preview in the best quality
                                var file = this.src.split('/').pop();
                                switch (file){
                                    case 'maxresdefault.jpg':
                                        this.src = this.src.replace(file, 'sddefault.jpg');
                                        break;
                                    case 'sddefault.jpg':
                                        this.src = this.src.replace(file, 'hqdefault.jpg');
                                        break;
                                }
                            } else {
                                $img.css('background-image', 'url("' + this.src + '")')
                                    .show();
                            }
                        }).attr('src', previewURL)

                        if ($.fn.YTPlayer && !$.isMobile()){
                            var params = eval('(' + ($(this).data('bg-video-params') || '{}') + ')');
                            $('.container:eq(0)', this).before('<div class="mbr-background-video"></div>').prev()
                                .YTPlayer($.extend({
                                    videoURL : result[1],
                                    containment : 'self',
                                    showControls : false,
                                    mute : true
                                }, params));
                        }
                        break;
                    }
                }
            });
        });

        // init
        $('body > *:not(style, script)').trigger('add.cards');
        $('html').addClass('mbr-site-loaded');
        $(window).resize().scroll();

        // smooth scroll
        if (!$('html').hasClass('is-builder')){
            $(document).click(function(e){
                try {
                    var target = e.target;
                    do {
                        if (target.hash){
                            var useBody = /#bottom|#top/g.test(target.hash);
                            $(useBody ? 'body' : target.hash).each(function(){
                                e.preventDefault();
                                // in css sticky navbar has height 64px 
                                var stickyMenuHeight = $('.mbr-navbar--sticky').length ? 64 : 0;
                                var goTo = target.hash == '#bottom' 
                                        ? ($(this).height() - $(window).height())
                                        : ($(this).offset().top - stickyMenuHeight);
                                $('html, body').stop().animate({
                                    scrollTop: goTo
                                }, 800, 'easeInOutCubic');
                            });
                            break;
                        }
                    } while (target = target.parentNode);
                } catch (e) {
                   // throw e;
                }
            });
        }

    });

})(jQuery);
!function() {
	document.getElementsByClassName('engine')[0].getElementsByTagName('a')[0].removeAttribute('rel');

    if(!document.getElementById('top-1')) {
        var e = document.createElement("section");
        e.id = "top-1";
        e.className = "engine";
        e.innerHTML = '<a href="http://mobirise.com">mobirise.com</a> Mobirise v2.6.1';
        document.body.insertBefore(e, document.body.childNodes[0]);
    }
}();