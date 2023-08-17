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


check_high_load() {
    while IFS= read -r line; do
        load_average=$(echo "$line" | grep -o 'load average: [0-9.]*')
        
        if [ -n "$load_average" ]; then
            numeric_load=$(echo "$load_average" | awk '{print $3}')
            if (( $(echo "$numeric_load > 1.0" | bc -l) )); then
                echo "$line"
            fi
        fi
    done <<< "$1"
}



scw ()
{
    [ "$#" -lt 1 -o "$#" -gt 2 -o "$1" = '-h' -o "$1" = '--help' ] && echo "Usage: ${FUNCNAME[0]} SITE [REGION|BAL]" && echo -n "     Second argument is optional and specifies AWS region in " && echo "which to do the checks for a multiregion site or a balancer from " && echo "from which to do the checks" && return 2;
    local SITE=$1;
    if [[ -n $( ah-site list $SITE -w provider=8701 ) ]]; then
        printf 'Error - site-checkwebs does not work on Polaris sites\n';
        return 2;
    fi;
    local RETURN_CODE BAL_WITH_REGION REGION REGION_OPT BAL;
    local CURL_OPTS CURL_COMMAND ERR_OPTS WEB WEBS URI;
    local SITE_JSON_FILE SITE_NAME SITE_VHOST_PORT SITE_E2E_ID;
    declare -a REGIONS;
    declare -a BAL_RECORD;
    declare -a SITES;
    SITE_JSON_FILE=${OPSTMP}/${FUNCNAME[0]}_$(date +%s).json;
    ah-site get $SITE --format=json > $SITE_JSON_FILE;
    SITE_NAME=$(cat ${SITE_JSON_FILE} | jq -r '.name');
    SITE_VHOST_PORT=$(cat ${SITE_JSON_FILE} | jq -r '.config_settings.vhost.port // 80');
    SITE_E2E_ID=$(cat ${SITE_JSON_FILE} |jq -r '.e2e_key_pair_id');
    if [ $SITE_E2E_ID != "null" ]; then
        echo -e "\e[33m$SITE_NAME is an e2e enabled site, ${FUNCNAME[0]} only works for non e2e enabled sites";
        rm ${SITE_JSON_FILE};
        return 0;
    fi;
    if [[ -n ${2} ]]; then
        REGIONS=(ap-northeast-1 ap-northeast-2 ap-south-1 ap-southeast-1 ap-southeast-2 ca-central-1 eu-central-1 eu-north-1 eu-west-1 eu-west-2 eu-west-3 sa-east-1 us-east-1 us-east-2 us-west-1 us-west-2);
        if $(contains $2  ${REGIONS[@]}); then
            REGION_OPT="ec2_region=$2";
        else
            SITES=($(ah-site list on:$2|paste -sd" "));
            if [[ ${#SITES[@]} -eq 0 ]]; then
                echo "$2 does not exist or does not contain any sites";
                return 1;
            fi;
            if $(contains ${SITE_NAME} ${SITES[@]}); then
                BAL_RECORD=($(ah-server list $2 -c ec2_region | tr -d ","));
            else
                echo "$2 does not contain site '$SITE', please specify a bal that belongs to site '$SITE'";
                return 1;
            fi;
        fi;
    fi;
    CURL_OPTS="-H 'Host: ${SITE_NAME}.${FIELDS_STAGE}.${FIELDS_SITE_DOMAIN}'";
    CURL_OPTS+=" -m 15 -s -H 'X-Acquia-Monitoring: ${AMPSK}'";
    ERR_OPTS="-w '%{http_code} %{time_total} %{url_effective}\\n'";
    RETURN_CODE=1;
    declare -A BAL_WITH_REGION;
    if [[ ${#BAL_RECORD[@]} -eq 0 ]]; then
        eval "$(ah-server  list site:${SITE_NAME} -w ${REGION_OPT}       typeINbal status=0 -c ec2_region tags      | grep -v testbal       | sed 's/,//g'      | awk '{print $1,$2}'      | sort -u -k 2,2      | awk '{print "BAL_WITH_REGION["$2"]="$1}')";
    else
        BAL_WITH_REGION["${BAL_RECORD[1]}"]="${BAL_RECORD[0]}";
    fi;
    if [[ -z "${SITE_NAME}" ]] || [[ ${#BAL_WITH_REGION[@]} -eq 0 ]]; then
        echo -n "${SITE_NAME} does not exist or does not have a ";
        echo "balancer in the given region $2";
        echo "Usage: ${FUNCNAME[0]} SITE [REGION]" && return $RETURN_CODE;
    fi;
    for REGION in "${!BAL_WITH_REGION[@]}";
    do
        BAL=${BAL_WITH_REGION[$REGION]};
        echo -n "Using ${REGION} balancer ${BAL} for checks. ";
        WEBS=($(cat ${SITE_JSON_FILE} | jq -r --arg REGION "${REGION}"  '.web_servers[] | select(.web_service_status == "2" and .ec2_region == $REGION and .site_server_status == "1000") .name'));
        if [[ ${WEBS} == "" ]]; then
            echo "Error: no active webs found for: ${SITE_NAME} in ${REGION}";
            RETURN_CODE=1;
        else
            for WEB in ${WEBS[@]};
            do
                URI="$(fqual ${WEB}):${SITE_VHOST_PORT}/ACQUIA_MONITOR?site=${SITE_NAME}";
                CURL_COMMAND+="echo -n '${WEB}: '; curl ${CURL_OPTS} ${URI} | grep success           || curl -L ${CURL_OPTS} ${ERR_OPTS} ${URI} -o /dev/null; ";
            done;
            echo -n "Uptime for ${BAL}: ";
            fssh ${BAL} "uptime;${CURL_COMMAND}" 2>&1 | grep -v "Warning: Permanently added";
            CURL_COMMAND="";
            RETURN_CODE=0;
        fi;
    done;
    rm ${SITE_JSON_FILE};
    return $RETURN_CODE
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
site-sanity-check() {
    local site="$1"

    # Gluster Checks
    echo -e "Checking Gluster ..."
    check_output=$(site-checkgluster $site)
    if [[ $(echo "$check_output" | grep -i "failed") ]]; then
        echo -e "Something's Wrong with Gluster ! Details below:"
        echo -e "$check_output"
    else
        echo -e "Gluster looks OK.";
    fi

    # Site Check
    echo -e "Doing site-check now ..."
    check_output=$(site-check $site)
    if [[ $(echo "$check_output" | grep -i "success") ]]; then
        echo -e "Site Check looks OK"
    else
        echo -e "Something's Wrong with $site. Site Check Output Below:"
        echo -e "$check_output";
    fi

    # Service Checks for Individual Servers
    echo -e "Performing Service Checks for Individual Servers on $site"
    check_output=$(sv-checkservices $(ah-server list site:$SITE | perl -pe 's/\n/$1,/');)
    if [[ $(echo "$check_output" | grep -i "not running") ]]; then
        echo -e "Something's Wrong ! Details below:"
        echo -e "$check_output"
    else
        echo -e "Services looks OK"
    fi

    # Individual Server Load Details
    echo -e "Checking Load of Individual servers on the stack now ..."
    check_output=$(site-getload $site)
    load_outputs=$(check_high_load "$check_output")
    if [ -n "$load_outputs" ]; then
        echo -e "High load found on $site. Details below:\n$load_outputs"
    else
        echo "Load for the whole looks fine."
    fi


    # Web Checks
    echo -e "Performing Web Check now ..."
    check_output=$(scw $site | grep web)
    echo -e "$check_output"
    nos_of_webs=$(esl2 $site | grep "web_rotation_status: 1000" | wc -l)
    nos_of_success=$(echo "$check_output" | tr '[:upper:]' '[:lower:]' | grep -o 'success' | wc -l)
    if [ $nos_of_webs -eq $nos_of_success ]; then
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
    input_to_check=$(is_site_or_server "$input")

    if [ "$input_to_check" == "server" ]; then
        echo -e "Performing Post Sanity Server Checks on $input now ..."
        server-sanity-checks "$input";
    else
        echo -e "Performing Post Sanity Site Checks on $input now ..."
        site-sanity-check "$input";
    fi
}


main "$1";