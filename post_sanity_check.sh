
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

[ $# -lt 1 ] && echo "Usage: ${FUNCNAME[0]} Site/Server" && return 0;
source essentials.sh;
source server_checks.sh;
source site_checks.sh;
main "$1";