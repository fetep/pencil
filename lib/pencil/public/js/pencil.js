/**
 * Created by JetBrains PhpStorm.
 * User: dan.staley
 * Date: 8/28/11
 * Time: 4:04 PM
 * To change this template use File | Settings | File Templates.
 */

var pencil = {
    selectors : {
      image_container : 'div#main img',
      timeslice : '#timeslice'
    },
    urls : {
      update : 'controller/update/action'
    },
    params : {
      //any params we need to send back.
    },
    config_version : '',
    reload_time : 20, //in seconds
    timer : null,
    bind : function(){
      pencil.timer = setInterval('pencil.reload_graphs()', pencil.reload_time*1000);
    },
    set_version : function(vers){
        pencil.config_version = vers;
    },
    stop_reloading : function(){
      clearInterval(pencil.timer);
    },
    check_config_version : function(vers){
        if(pencil.config_version == vers){
            //its same version, no need to refresh
        }else{
            //its not the same, lets reload teh page
            pencil.reload_page();
        }
    },
    check_for_updates : function(){
        /*
         * Response should look like this
         *
         * {
         *  status : true|false,
         *  version: version_number,
         *  timeslice: timeslice_text
         *  [,error : optional error]
         *  }
         */
        jQuery.post(pencil.urls.update, pencil.params, function(data){
            if(data.status){
                //update our timeslice html
                jQuery(pencil.selectors.timeslice).html(data.timeslice);
                //lets update the version and check it if we need to update the page
                pencil .check_config_version(data.version);
            }else{
                //there was a problem with our update
                error = (typeof(data.error) == "undefined") ? "There was a problem updating the page." : data.error;
                //alert(error); //removed for now while testing 
                pencil.log(error);
            }
        }, 'json');
    },
    reload_page : function(){
        document.location.reload();
    },
    reload_graphs : function(){
        //process each image
        jQuery(pencil.selectors.image_container).each(function(i,img){
            var src = jQuery(this).attr('src');
            var cnt = jQuery(this).attr('cnt');
            if(typeof(cnt) == "undefined"){
                cnt = 0;
                jQuery(this).attr('cnt', 0);
            }
            cnt = parseInt(cnt)+parseInt(1);
            jQuery(this).attr('src', src);
            jQuery(this).attr('cnt', cnt);
            jQuery(this).attr('alt','This image has been reload '+cnt+' times.');
        });
    },
    log : function(msg){
        try{ console.log(msg); }catch(e){/* do nothing */ }
    }
};

//bind our reload..
pencil.bind();