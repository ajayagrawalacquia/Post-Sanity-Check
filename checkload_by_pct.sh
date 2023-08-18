
check_high_load_by_pct() {
    webloads_path=$1
    echo $webloads_path
    for line in $(cat $webloads); do
        load=$(echo -e "$line" | awk '{print $11}' | tr -d '%' | bc -l);
        if [[ load > 2.0 ]]; then
            echo -e "$line"
        fi
    done
}


site=$1
echo -e "\n[ $(date) ] - Checking Load of Individual servers by Percentage on the stack now ..."
check_output=$(site-getloadpct $site | sed '1d')
echo -e "$check_output" > $OPSTMP/get_load_pct_$site
load_outputs=$(check_high_load_by_pct "$OPSTMP/get_load_pct_$site")