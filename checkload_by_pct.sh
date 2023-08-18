
check_high_load_by_pct() {

}


site=$1
echo -e "\n[ $(date) ] - Checking Load of Individual servers by Percentage on the stack now ..."
check_output=$(site-getloadpct $site | sed '1d')
echo -e "$check_output" > $OPSTMP/get_load_pct_$site
load_outputs=$(check_high_load_by_pct "$OPSTMP/get_load_pct_$site")