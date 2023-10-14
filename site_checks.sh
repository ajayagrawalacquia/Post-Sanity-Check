# - - - - - - - - - - Site Checks - - - - - - - - - -
site-sanity-checks() {
    local site="$1"

    # Gluster Checks
    echo -e "[ $(date) ] - Checking Gluster ..."
    check_output=$(site-checkgluster $site)
    if [[ $(echo "$check_output" | grep -i "failed") ]]; then
        echo -e "Something's Wrong with Gluster ! Details below:"
        echo -e "$check_output"
    else
        echo -e "Gluster looks OK.";
    fi

    # Site Check
    echo -e "\n[ $(date) ] - Doing site-check now ..."
    check_output=$(site-check $site 2> /dev/null);
    if [[ $(echo "$check_output" | grep -i "success") ]]; then
        echo -e "Site Check looks OK"
    else
        echo -e "Something's Wrong with $site. Site Check Output Below:"
        echo -e "$check_output";
    fi

    # Service Checks for Individual Servers
    echo -e "\n[ $(date) ] - Performing Service Checks for Individual Servers on $site now ..."
    check_output=$(sv-checkservices $(ah-server list site:$SITE | perl -pe 's/\n/$1,/');)
    if [[ $(echo "$check_output" | grep -i "not running") ]]; then
        echo -e "Something's Wrong ! Details below:"
        echo -e "$check_output"
    else
        echo -e "Services looks OK"
    fi


    # Individual Server Load Details by Percentage
    echo -e "\n[ $(date) ] - Checking Load of Individual servers by Percentage on the stack now ..."
    touch "$OPSTMP/loadchecktemp$site"
    site-getloadpct_with_no_color "$site" | sed '1d' 2> /dev/null > "$OPSTMP/loadchecktemp$site" | tee /dev/null
    check_output=$(cat "$OPSTMP/loadchecktemp$site")

    if [ -n "$check_output" ]; then
        load_outputs=$(check_high_load_by_pct "$check_output")
        if [ -n "$load_outputs" ]; then
            echo -e "High load found on some server(s). Details below:\n$load_outputs"
        else
            echo "Load for the whole stack looks fine."
        fi
    else
        echo "There are no dedicated web servers for $site !"
    fi




    # Web Checks
    echo -e "\n[ $(date) ] - Performing Web Check now ..."
    site-checkwebs $site 2> /dev/null > $OPSTMP/webchecktemp$site | tee /dev/null
    check_output=$(cat $OPSTMP/webchecktemp$site)
    nos_of_webs=$(esl2 $site | grep "web_rotation_status: 1000" | wc -l)
    nos_of_success=$(echo "$check_output" | tr '[:upper:]' '[:lower:]' | grep -o 'success' | wc -l)
    if [ $nos_of_webs -eq $nos_of_success ]; then
        echo "Web Checks looks OK"
    else
        echo "Something's Wrong Here. Details Below:"
        echo -e "$check_output"
    fi
    rm $OPSTMP/webchecktemp$site



    # Web Rotation Status
    touch $OPSTMP/webchecktemp$site
    echo -e "\n[ $(date) ] - Checking Web Rotation Status now ..."
    check_output=$(site-getwebrotationstatus $site)
    # webs_in_rotation=$(echo -e "$check_output" | grep 1000 | awk '{print $1}')
    # nos_webs_in_rotation=$(echo -e "$webs_in_rotation" | wc -l)

    webs_out_of_rotation=$(echo -e "$check_output" | grep 1001 | awk '{print $1}')
    nos_webs_out_of_rotation=$(echo -e "$webs_out_of_rotation" | wc -l)

    for s in $webs_out_of_rotation
    do
        oob_or_not=$(ah-server list $s -c tags)
        if [[ "$oob_or_not" != *"oob"* ]]; then
            echo -e "$s" >> $OPSTMP/webchecktemp$site
        fi
    done

    if [ -s "$OPSTMP/webchecktemp$site" ]; then
        echo -e "$(cat $OPSTMP/webchecktemp$site | wc -l) Web Servers which are NOT tagged as OOB and are NOT in Rotation: $(cat $OPSTMP/webchecktemp$site | tr '\n' ',' | sed 's/.$//')"
        rm $OPSTMP/webchecktemp$site
    else
        echo -e "Web Rotation Checks Passed."
    fi






    # Monitoring Status for Site
    echo -e "\n[ $(date) ] - Checking Monitoring Status for $site now ..."
    check_output=$(site-mon get $site)
    if [[ $(echo "$check_output" | grep -i "absent") ]]; then
        echo -e "$check_output"
        echo -e "Looks like Monitoring is not enabled for $site. Use site-monenable $site to enable Monitoring if you have missed."
    else
        echo -e "Monitoring is enabled for $site.";
    fi



    # Monitoring Status for Individual Servers
    echo -e "\n[ $(date) ] - Checking Monitoring Status for Individual Servers on $site now ..."
    for s in $(ah-server list site:$site)
    do
        status=$(ah-server list $s -c monitoring_status | awk '{print $2}')
        if [ "$status" -ne 2 ]; then
            server_tag=$(ah-server tag list $s 2> /dev/null)
            if [[ $server_tag == *monitor_suppress* ]]; then
                echo -e "Monitoring is Intentionally Suppressed for $s and hence, can be IGNORED !"
            else
                echo -e "$s" >> $OPSTMP/monitoring_check_Server_for_$site
            fi
        fi
    done

    if [ -s "$OPSTMP/monitoring_check_Server_for_$site" ]; then
        echo -e "$(cat $OPSTMP/monitoring_check_Server_for_$site | wc -l) Server(s) are/is NOT being Monitored: $(cat $OPSTMP/monitoring_check_Server_for_$site | tr '\n' ',' | sed 's/.$//')"
        rm $OPSTMP/monitoring_check_Server_for_$site
    else
        echo -e "All the Servers on $site are being Monitored."
    fi




    # Memcache Service Status on Individual Web Servers
    echo -e "\n[ $(date) ] - Checking Memcache Status for Individual Web Servers now ..."
    webs=$(site-getwebrotationstatus $site 2> /dev/null | awk '{print $1}')
    for w in $webs; do
        status=$(ah-server get $w | grep memcache_service_status | awk '{print $2}')
        if [ "$status" -ne 2 ]; then
            echo -e "$w" >> $OPSTMP/memcache_check_Server_for_$site
        fi
    done

    if [ -s "$OPSTMP/memcache_check_Server_for_$site" ]; then
        echo -e "$(cat $OPSTMP/memcache_check_Server_for_$site | wc -l) Web Server(s) have Memcache Disabled: $(cat $OPSTMP/memcache_check_Server_for_$site | tr '\n' ',' | sed 's/.$//')"
        rm $OPSTMP/memcache_check_Server_for_$site
    else
        echo -e "Memcache is Enabled for all the Web Servers."
    fi


    # Memcache Value Checks
    echo -e "\n[ $(date) ] - Checking if appropriate Memcache Memory is allocated or not..."
    
    webs_in_site=$(site-getwebrotationstatus $site 2> /dev/null | awk '{print $1}')
    webs_have_memcache=0
    webs_no_memcache=0
    
    for w in $webs_in_site
    do
        memcache_memory_set=$(ah-server get $w | grep -i "server_settings.memcached.conf.-m" | awk '{print $2}')

        if [ -z "$memcache_memory_set" ]; then
            ((webs_no_memcache++))
        else
            # echo -e "$w - $memcache_memory_set"
            check_memcache_memory_value $w;
            ((webs_have_memcache++))
        fi

        echo ""
    done



}




# Command to check tags - "ah-server list web-46562 -c tags"

