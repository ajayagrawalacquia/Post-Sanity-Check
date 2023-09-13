# some supporting functions
fqual ()
{
    if [ "$FACCT_TYPE" != "managed" ]; then
        echo "You're not currently in a managed account.";
        return 1;
    fi;
    FHOST=$1;
    shift;
    if [ "$FHOST" = "master" ]; then
        echo -n "$FHOST.e.$FIELDS_STAGE.$FIELDS_MASTER_DOMAIN";
    else
        echo -n "$FHOST.$FIELDS_STAGE.$FIELDS_SERVER_DOMAIN";
    fi
}

fssh ()
{
    if [ "$FACCT_TYPE" != "managed" ]; then
        echo "You're not currently in a managed account.";
        return 1;
    fi;
    FHOST=$1;
    shift;
    FUSER=$(get_fuser);
    ssh -A -p 40506 -i $FIELDS_SSH_ID -o StrictHostKeyChecking=no $FUSER@`fqual $FHOST` $@
}

get_fuser ()
{
    if [ -z "$FIELDS_SSH_USER" ]; then
        echo $USER;
    else
        echo $FIELDS_SSH_USER;
    fi
}



check_high_load_by_pct() {
    webloads="$1"
    echo "$webloads" | sed -r 's/\x1B\[[0-9;]*[mK]//g' | while IFS= read -r line; do
        load=$(echo "$line" | awk '{print $11}' | tr -d '%')
        rounded_load=$(ruby -e "puts $load.to_f.round")
        if [ $rounded_load -gt 70 ]; then   # Assuming more than 70% is high load
            echo -e "$line"
        fi
    done
}



check_space_filled() {
    df_output="$1"
    while IFS= read -r line; do
        percet_filled=$(echo -e "$line" | awk '{print $5}' | tr -d '%')
        if [[ $percet_filled -gt 85 ]]; then    # Assuming if we notify before 90%, the customer will have some time to do clean up.
            echo -e "$line"
        fi
    done <<< "$df_output"
}


# check_failed_sites() {
#     sites_list="$1"
#     echo "$sites_list" | while IFS= read -r line; do
#         status=$(echo "$line" | awk '{print $2}')
#         if [ $status -eq 'failed' ]; then
#             echo -e "$line"
#         fi
#     done
# }




# Check if the Input is site or Server
is_site_or_server() {
    local input="$1"

    if [[ "$input" =~ [a-zA-Z]+-[0-9]+ ]]; then
        echo "server"
    else
        echo "site"
    fi
}



# Function to check if Memcache Memory is set appropriately or not.

str_to_int() {
    local input="$1"
    echo "$((input))"
}


get_nearest100() {
  local input=$1
  local remainder=$((input % 100))
  
  if [ $remainder -lt 50 ]; then
    echo $((input - remainder))
  else
    echo $((input + (100 - remainder)))
  fi
}


check_memcache_memory_value() {
    local server="$1"
    memcache_memory_set=$(ah-server list $server -c memcached.conf:-m | awk '{print $2}')
    memcache_memory_set=$(str_to_int "$memcache_memory_set")

    total_memory_in_server=$(fssh $server free -t -m 2> /dev/null | grep "Mem" | awk '{ print $2}')
    total_memory_in_server=$(str_to_int "$total_memory_in_server")
    memcache_multiplier=0.7

    approx_desired_memcache=$(echo "$total_memory_in_server * $memcache_multiplier" | bc -l)
    approx_desired_memcache=$(printf "%.0f" "$approx_desired_memcache")
    approx_desired_memcache=$(get_nearest100 $approx_desired_memcache)

    # echo -e "Total Memory in $server = $total_memory_in_server\nMemcache Memory = $memcache_memory_set\nApprox Desired Memcache = $approx_desired_memcache\n\n\n\n"

    if [ "$memcache_memory_set" -lt "$approx_desired_memcache" ]; then
      echo -e "\t$server has Insufficient Memcache Memory Set."
      echo -e "\tIt should have atleast $approx_desired_memcache MB set as Memcache (which currently is $memcache_memory_set)"
      echo -e "\t\t Use this command to set it now - ah-server edit $server -c memcached.conf:-m=$approx_desired_memcache"
    else
      echo -e "$server - OK ✓"
    fi
}



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
    check_output=$(site-getloadpct $site | sed '1d')
    load_outputs=$(check_high_load_by_pct "$check_output")
    if [ -n "$load_outputs" ]; then
        echo -e "High load found on some server(s). Details below:\n$load_outputs"
    else
        echo "Load for the whole stack looks fine."
    fi



    # Web Checks
    echo -e "\n[ $(date) ] - Performing Web Check now ..."
    site-checkwebs $site | grep web 2> /dev/null > $OPSTMP/webchecktemp$site | tee /dev/null
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
            echo -e "$s" >> $OPSTMP/monitoring_check_Server_for_$site
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
    webs=$(ah-server list site:$site | grep web)
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
    
    webs_in_site=$(ah-server list site:$site -w typeIN'web')
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
    done



}




# Command to check tags - "ah-server list web-46562 -c tags"






# - - - - - - - - - - Server Checks - - - - - - - - - -

server-sanity-checks () {
    local server="$1"

    # Monitoring Status
    echo -e "[ $(date) ] - Checking Monitoring Status Now ..."
    check_output=$(sv-monstatus $server | awk '{print $2}' | sed '1d');
    if [[ $(echo "$check_output" | grep -i "2") ]]; then
        echo -e "Monitoring is Enabled for $server"
    else
        echo -e "Monitoring status is $check_output. Use sv-monenable $server to enable the monitoring."
    fi


    # Service Status
    echo -e "\n[ $(date) ] - Checking Service Status Now ..."
    check_output=$(sv-checkservices $server);
    if [[ $(echo "$check_output" | grep -i "not running") ]]; then
        echo -e "Something's Wrong ! Details below:"
        echo -e "$check_output"
    else
        echo -e "Services looks OK"
    fi

    # Site Check for all the sites on the server
    echo -e "\n[ $(date) ] - Performing Site Check for all the Sites in $server..."
    all_sites=$(ah-site list on:$server)
    all_sites_csv=$(echo -e "$all_sites" | tr '\n' ',' | rev | cut -c2- | rev)
    nos_all_sites=$(echo -e "$all_sites" | wc -l)

    site_checks=$(for site in $all_sites; do
        site_check=$(site-check $site 2> /dev/null)
        if [[ "$site_check" == *"success"* ]]; then
            echo "$site : success"
        else
            echo "$site : failed"
        fi
    done)

    failed_sites=$(echo "$site_checks" | awk -F ' : ' '/failed/{print $1}')

    if [ -z "$failed_sites" ]; then
        echo "$nos_all_sites/$nos_all_sites Site(s) on $server Passed the Site Checks"
    else
        failed_sites_list=$(echo -e "$failed_sites" | awk '{print $1}' | rev | cut -c2- | rev)
        failed_sites_list_csv=$(echo -e "$failed_sites" | awk '{print $1}' | rev | cut -c2- | rev | tr '\n' ',' | rev | cut -c2- | rev)
        nos_failed_sites=$(echo -e "$failed_sites" | wc -l)
        echo -e "$nos_failed_sites/$nos_all_sites Site(s) on $server Failed Site Check - $failed_sites_list_csv"
    fi



    # No Extra Volumes are left (eg no extra /mnt/resize-wf-* type vols)
    echo -e "\n[ $(date) ] - Checking if any Resize Volumes are attached on $server..."
    vollist_output=$(sv-vollist $server)
    if [[ "$vollist_output" == *"resize"* ]]; then
        echo -e "Looks like a Resize Volume is attached to $server. Details below:"
        echo -e "$vollist_output" | grep -i 'resize'
    else
        echo -e "Volumes looks OK. No Resize Workflow Volumes attached."
    fi


    # Server Status
    echo -e "\n[ $(date) ] - Checking Server Status now..."
    status=$(ah-server status $server);
    impaired_count=$(grep -o -i "impaired" <<< "$status" | wc -l);
    passed_count=$(grep -o -i "passed" <<< "$status" | wc -l);
    failed_count=$(grep -o -i "failed" <<< "$status" | wc -l);
    if [[ $passed_count -eq 2 && $impaired_count -eq 0 && $failed_count -eq 0 ]]; then
        echo -e "Server Status Check Passed."
    else
        echo -e "Something's Wrong ! Details below:\n$status"
    fi


    # Server Load
    echo -e "\n[ $(date) ] - Checking Server Load now..."
    server_load_by_pct=$(site-getloadpct $(ah-site list on:$server | head -n 1) | grep $server)
    check_output=$(check_high_load_by_pct "$server_load_by_pct")
    if [ -n "$check_output" ]; then
        echo -e "$server is on High Load. Details below:\n$server_load_by_pct"
    else
        echo "Server Load looks fine"
    fi


    # Server Load Core-Wise
    echo -e "\n[ $(date) ] - Checking Core-Wise Server Load now..."
    nos_of_cores=$(fssh $server "nproc" 2> /dev/null)
    core_wise_load_pct=$(fssh $server "mpstat -P ALL 1 1" 2> /dev/null | awk '/^[0-9]/ {print "Core " $3 ":", 100 - $NF "%"}' | tail -n +3)
    
    echo -e "$server has total $nos_of_cores cores and below are core-wise checks:"
    while IFS= read -r line; do
      core_name=$(echo "$line" | cut -d ':' -f 1)
      load_pct=$(echo "$line" | awk '{print $NF}' | tr -d '%') # Remove the percentage sign

      # Convert load_pct to an integer
      load_pct_int=${load_pct%.*}

      if [ "$load_pct_int" -gt 75 ]; then
        echo "$core_name: High Load [ $load_pct% ]"
      else
        echo "$core_name: OK ✓"
      fi
    done <<< "$core_wise_load_pct"



    # Space Checks
    echo -e "\n[ $(date) ] - Performing Space Checks..."
    server_df_output=$(sv-df $server 2> /dev/null | sed '1d' | sed '$d')
    check_output=$(check_space_filled "$server_df_output")

    if [ -z "$check_output" ]; then
        echo "Space Check Passed."
    else
        echo "Mountpoints with more than 85% space filled detected. Details below:"
        echo "$check_output"
    fi


    # Just echoing here to use sv-get status if any further details are required. (Just to remove clutter from the overall output)
    echo -e "\nNote: Please feel free to use sv-getstatus $server, if you want some additional configuration details like ec2_id, etc for $server."
}






# sv-getstatus Output (as it gives some neat outputs)


# Main Function
main() {
    local input="$1"
    input_to_check=$(is_site_or_server "$input")

    if [ "$input_to_check" == "server" ]; then
        echo -e "- - - - - - - - - - Performing Post Sanity Server Checks on $input [ $(ah-server list $input -c ami_type | awk '{print $2}') ] now - - - - - - - - - -"
        server-sanity-checks "$input";
    else
        echo -e "- - - - - - - - - - Performing Post Sanity Site Checks on $input now - - - - - - - - - -"
        site-sanity-checks "$input";
    fi
}


main "$1";
