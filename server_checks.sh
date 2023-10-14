
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


