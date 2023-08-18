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


check_high_load() {
    while IFS= read -r line; do
        load_average=$(echo "$line" | grep -o 'load average: [0-9.]*')
        
        if [ -n "$load_average" ]; then
            numeric_load=$(echo "$load_average" | awk '{print $3}')
            if (( $(echo "$numeric_load > 2.0" | bc -l) )); then    # assuming we need to check if load is above 1.0
                echo "$line"
            fi
        fi
    done <<< "$1"
}




check_high_load_by_pct() {
    webloads="$1"
    echo -e "FilePath is $webloads"

    grep -E 'load average: [0-9]+(\.[0-9]+)?%' "$webloads" |
    while IFS= read -r line; do
        echo -e "Checking $line"
        # Extract the load percentage from the line
        load=$(echo "$line" | grep -oE 'load average: [0-9]+(\.[0-9]+)?%' | grep -oE '[0-9]+(\.[0-9]+)?%' | tr -d '%')
        echo -e "$line is $load"
        # Check if load is not empty and is greater than 10%
        if [ -n "$load" ] && [ $(echo "$load" | sed 's/%$//' | awk '{if ($1 > 10) print 1; else print 0}') -eq 1 ]; then
            echo "$line"
        fi
    done
}



# Check if the Input is site or Server
is_site_or_server() {
    local input="$1"
    
    if [[ "$input" =~ [a-zA-Z]+-[0-9]+ ]]; then
        echo "server"
    else
        echo "site"
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

    # Individual Server Load Details
    echo -e "\n[ $(date) ] - Checking Load of Individual servers on the stack now ..."
    check_output=$(site-getload $site)
    # check_output=$(echo -e "$check_output" | sed '1d')
    load_outputs=$(check_high_load "$check_output")
    if [ -n "$load_outputs" ]; then
        echo -e "High load found on some server(s). Details below:\n$load_outputs"
    else
        echo "Load for the whole stack looks fine."
    fi


    # Individual Server Load Details by Percentage
    echo -e "\n[ $(date) ] - Checking Load of Individual servers by Percentage on the stack now ..."
    check_output=$(site-getloadpct $site | sed '1d')
    echo -e "$check_output" > $OPSTMP/get_load_pct_$site
    load_outputs=$(check_high_load_by_pct "$OPSTMP/get_load_pct_$site")



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


}




# Command to check tags - "ah-server list web-46562 -c tags"






# - - - - - - - - - - Server Checks - - - - - - - - - -

server-sanity-checks () {
    echo ""
}
# Monitoring Status
# Service Status
# Site Check for all the sites on the server ? (I think this might get pretty long for some servers. But just noting it down here)
# No Extra Volumes are left (eg no extra /mnt/resize-wf-* type vols)
# Server Status
# Server Load
# sv-getstatus Output (as it gives some neat outputs)
# Space Checks
# Volume Listing


# Main Function
main() {
    local input="$1"
    input_to_check=$(is_site_or_server "$input")

    if [ "$input_to_check" == "server" ]; then
        echo -e "- - - - - - - - - - Performing Post Sanity Server Checks on $input now - - - - - - - - - -"
        server-sanity-checks "$input";
    else
        echo -e "- - - - - - - - - - Performing Post Sanity Site Checks on $input now - - - - - - - - - -"
        site-sanity-checks "$input";
    fi
}


main "$1";