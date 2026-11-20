// The small scripts the overlay gives to pages: the "you are in the overlay" flag for YOUR map site (mode, layout, size),
// a steady pixel ratio so the map is never blurry, the TOC video wall rule, and the YouTube ad skipper.
import Foundation

enum PageScript {
    static func jsString(_ s: String) -> String {
        var out = "'"
        for u in s.unicodeScalars {
            if u == "\\" || u == "'" { out += "\\" }
            if u.value >= 32 && u.value < 127 { out.unicodeScalars.append(u) }
        }
        return out + "'"
    }

    // host = the map site's host name (the script does nothing on any other site)
    // mode = "full" (tablet expanded) or "mini" (frameless live corner view)
    // The page gets the real state in window.__tacHost; __tacApply works out what it should hear. In the minimized live view
    // the map site goes into its "mini" mode, which keeps ONLY ONE pinned feed connected and hides everything else - so a TOC
    // video wall that is open in the live view would lose every stream and show black. While the TOC video wall is open the
    // page is therefore told "full" instead, so all its streams stay connected and playing; when the wall is closed it gets
    // "mini" again. This is done here, in the overlay, so the website itself does not have to change.
    static func home(host: String, tag: String, aspect: Double, mode: String, vw: Int, vh: Int, dpr: Double) -> String {
        let aspectText = String(format: "%.3f", aspect)
        let dprText = String(format: "%.2f", dpr)
        return #"""
        (function(){if(location.hostname!==\#(jsString(host)))return;
        try{Object.defineProperty(window,'devicePixelRatio',{get:function(){return \#(dprText);},configurable:true});}catch(e){}
        window.__tacHost={layout:\#(jsString(tag)),aspect:\#(aspectText),mode:\#(jsString(mode)),viewport:{w:\#(vw),h:\#(vh)}};
        if(!window.__tacApply){
          window.__tacApply=function(force){
            var h=window.__tacHost,m=h.mode;
            if(m==='mini'){try{if(document.querySelector('[role="dialog"][aria-label="TOC Video Wall"]'))m='full';}catch(e){}}
            var key=m+'|'+h.layout+'|'+h.aspect;
            if(!force&&key===window.__tacKey&&document.documentElement&&document.documentElement.getAttribute('data-overlay-mode')===m)return;
            window.__tacKey=key;
            var o={tablet:true,layout:h.layout,aspect:h.aspect,mode:m,viewport:h.viewport};
            window.TAC_OVERLAY=o;
            var de=document.documentElement;if(de){de.setAttribute('data-overlay',h.layout);de.setAttribute('data-overlay-mode',m);}
            try{window.dispatchEvent(new CustomEvent('tacoverlay-mode',{detail:o}));}catch(e){}
          };
          document.addEventListener('DOMContentLoaded',function(){window.__tacApply(true);});
          window.setInterval(function(){window.__tacApply(false);},400);
        }
        window.__tacApply(true);})();
        """#
    }

    static let youTube = #"""
    (function(){
    if(!/(^|\.)youtube\.com$/.test(location.hostname))return;
    var css='ytd-ad-slot-renderer,ytd-in-feed-ad-layout-renderer,ytd-display-ad-renderer,ytd-promoted-sparkles-web-renderer,ytd-promoted-video-renderer,ytd-banner-promo-renderer,ytd-statement-banner-renderer,ytd-companion-slot-renderer,ytd-action-companion-ad-renderer,#masthead-ad,#player-ads,.video-ads,.ytp-ad-module,.ytp-ad-overlay-container,.ytp-ad-image-overlay{display:none!important}';
    function addCss(){var s=document.createElement('style');s.textContent=css;(document.head||document.documentElement).appendChild(s);}
    if(document.documentElement)addCss();else document.addEventListener('DOMContentLoaded',addCss);
    var was=null;
    setInterval(function(){
     var p=document.querySelector('.html5-video-player');if(!p)return;
     var v=p.querySelector('video.html5-main-video')||p.querySelector('video');
     var ad=p.classList.contains('ad-showing')||p.classList.contains('ad-interrupting');
     if(ad&&v){
      if(was===null)was=v.muted;
      v.muted=true;
      try{v.playbackRate=16;}catch(e){}
      if(isFinite(v.duration)&&v.duration>0&&v.currentTime<v.duration-0.2){try{v.currentTime=v.duration-0.1;}catch(e){}}
     }else if(was!==null&&v){v.muted=was;v.playbackRate=1;was=null;}
     var b=document.querySelector('.ytp-skip-ad-button,.ytp-ad-skip-button,.ytp-ad-skip-button-modern,.ytp-ad-skip-button-container button');
     if(b)b.click();
    },250);
    })();
    """#
}
