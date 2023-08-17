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
site-sanity-check() {
    local site="$1"

    # Gluster Checks
    echo -e "[ $(date) ] - Checking Gluster ..."
    site-checkgluster $site;

    # Site Check
    check_output=$(site-check $site)
    if [[ $(echo "$check_output" | grep -i "success") ]]; then
        echo -e "Site Check looks OK"
    else
        echo -e "Something's Wrong with $site. Site Check Output Below:"
        echo -e "$check_output";
    fi

    # Service Checks for Individual Servers
    check_output=$(sv-checkservices $(ah-server list site:$SITE | perl -pe 's/\n/$1,/');)
    if [[ $(echo "$check_output" | grep -i "not running") ]]; then
        echo -e "Something's Wrong ! Details below:"
        echo -e "$check_output"
    else
        echo -e "Services looks OK"
    fi

    # Individual Server Load Details
    site-getload $site

    # Web Checks
    check_output=$(site-checkwebs $site | grep web)
    nos_of_webs=$(esl $site | grep web- | wc -l)
    nos_of_success=$(echo "$check_output" | tr '[:upper:]' '[:lower:]' | grep -o 'success' | wc -l)
    if [ "$nos_of_webs" -eq "$nos_of_success" ]; then
        echo "Web Checks looks OK"
    else
        echo "Something's Wrong Here. Details Below:"
        echo -e "$check_output"
    fi
}



# Web Rotation Status
# Monitoring Status

# - - - - - - - - - - Server Checks - - - - - - - - - -
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
    input_to_check=$(is_site_or_server "input")

    if [ "$input_to_check" == "server" ]; then
        echo -e "Performing Post Sanity Server Checks on $input_to_check now ..."
        server-sanity-checks "$input_to_check";
    else
        echo -e "Performing Post Sanity Site Checks on $input_to_check now ..."
        site-sanity-check "$input_to_check";
    fi
}


[ $# -lt 1 ] && echo "Usage: ${FUNCNAME[0]} SITE/SERVER" && return 0;
local user_input=$1;
main "$user_input";
