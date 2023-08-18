check_high_load_by_pct() {
    echo $webloads_path
    while IFS= read -r line; do
        echo -e "$line" | awk '{print $11}' | tr -d '%' | bc -l
    done <<< $webloads_path
}


site=$1
echo -e "\n[ $(date) ] - Checking Load of Individual servers by Percentage on the stack now ..."
check_output=$(site-getloadpct $site | sed '1d')
echo -e "$check_output" > $OPSTMP/get_load_pct_$site
load_outputs=$(check_high_load_by_pct "$OPSTMP/get_load_pct_$site")
echo -e "$load_outputs"