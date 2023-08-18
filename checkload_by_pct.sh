check_high_load_by_pct() {
    webloads="$1"
    echo "$webloads" | sed -r 's/\x1B\[[0-9;]*[mK]//g' | while IFS= read -r line; do
        load=$(echo "$line" | awk '{print $11}' | tr -d '%')
        rounded_load=$(ruby -e "puts $load.to_f.round")
        if [ $rounded_load -gt 10 ]; then
            echo -e "$line"
        fi
    done
}



site=$1
echo -e "\n[ $(date) ] - Checking Load of Individual servers by Percentage on the stack now ..."
check_output=$(site-getloadpct $site | sed '1d')
load_outputs=$(check_high_load_by_pct "$check_output")
echo -e "$load_outputs"