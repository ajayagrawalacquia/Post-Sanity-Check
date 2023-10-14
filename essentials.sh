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
    local webloads="$1"
    while IFS= read -r line; do
        local load=$(echo "$line" | awk '{print $11}' | tr -d '%')
        local rounded_load=$(printf "%.0f" "$load")
        if [ "$rounded_load" -gt 70 ]; then
            echo -e "$line"
        fi
    done <<< "$webloads"
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

