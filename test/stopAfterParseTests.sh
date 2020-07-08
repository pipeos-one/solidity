#!/bin/bash

while read -r file; do
	ALLOUTPUT=$(build/solc/solc --combined-json ast,compact-format --pretty-json "$file" --stop-after parsing 2>&1)
	if test "$?" != "0"; then
		# solc returned failure. Compilation errors and unimplemented features
		# are okay, everything else is a failed test (segfault)
		if ! echo "$ALLOUTPUT" | grep -e "Unimplemented feature:" -e "Error:" -q; then
			echo "Test failed on $file:";
			echo "$ALLOUTPUT"
			exit 1;
		fi
	else
		echo -n .
	fi
done < <(find test -iname "*.sol")
echo "";
