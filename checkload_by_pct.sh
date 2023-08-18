check_high_load_by_pct() {
    webloads="$1"
    echo "$webloads" | while IFS= read -r line; do
        echo "Processing line: $line"
    done
}


site=$1
echo -e "\n[ $(date) ] - Checking Load of Individual servers by Percentage on the stack now ..."
check_output=$(site-getloadpct $site | sed '1d')
load_outputs=$(check_high_load_by_pct "$check_output")
echo -e "$load_outputs"