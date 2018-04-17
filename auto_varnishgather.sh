#!/bin/bash
# (c) Sergey Bulavintsev 2018.04.17
# Script to collect varnishgather information from varnish server and upload them into Varnish support filebin
#############################################################

####################FUNCTIONS################################
usage()
{
	cat <<_EOF_
Usage: $0 [-n|--name name] [-s|--server server] [-b|--bin] [-h] 
Script to execute varnishgather on remote Varnish server and upload it to 
Varnish support bin.

 -n|--name   <name>        Varnish instance name(number)
 -s|--server <server>      IP address or hostname of remote server
 -b|--bin    <bin>         Mandatory: Bin to upload file
 -c|--collect              Don't upload reports to Varnish support
 -h                        Show this text.
If name is not provided, script will gather information on all instances.
If bin is not provided, script will create a new bin and upload files into
this bin.
Server argument is mandatory
_EOF_
	exit 1
}

createbin()
{
	echo "Bin for kering"> /tmp/Kering-bin.txt
	BIN=$(curl -s --data-binary "@/tmp/Kering-bin.txt" https://filebin.varnish-software.com/ -H "filename: Kering.txt" | grep \"bin\"\: | awk '{print $2}' | tr -dc '[:alnum:]\n\r')
	if [ -z $BIN ]; then
		echo "Creating BIN unsussessful!"
	else 
		echo "File BIN for upload created!"
	fi
}

######################MAIN CYCLE#############################
POSITIONAL=()
while [[ $# -gt 0 ]]
do
	key="$1"

	case $key in
		-n|--name)
		NAME="$2"
		shift # past argument
		shift # past value
		;;
		-h|--help) usage; exit 0;;
		-s|--server)
		SERVER="$2"
		shift # past argument
		shift # past value
		;;
        -b|--bin)
        BIN="$2"
		shift # past argument
		shift # past value
		;;
		-c|--collect)
		COLLECT=true
		shift
		shift
		;;
		*) echo "Please check your arguments"; exit 1;;
	esac
done
set -- "${POSITIONAL[@]}" # restore positional parameter

######################CHECK ARGUMENTS########################
if [ -z "$SERVER" ];then
	echo "Please provide server to gather informations using the -s key"
	echo "Run $0 -h for help"
	exit 1
fi

if [ -z $BIN ]; then
	if [ -z $COLLECT ]; then 
		createbin
	fi
fi
echo "-------Using following arguments------------------------"
echo "Instance=$NAME"
echo "Bin=$BIN"
echo "Server=$SERVER"
echo "--------------------------------------------------------"

if [[ $# -eq 0 ]]; then 
	if  ping -w 1 -c 1 $SERVER | grep -q '1 received'; then
		echo "Server is pingable"
		if [[ $SERVER = *varnish* ]] || [[ $SERVER = *vac* ]]; then
            echo "$SERVER: This is correct Varnish server!"
		else
			echo "$SERVER: This is not varnish server!"
			exit 3
		fi

	else
		echo "Server not available!"
		exit 2
	fi
fi
######################GENERATE AND COPY REPORT###############
echo "$SERVER: Removing old varnishgather tar files"
ssh root@$SERVER "rm -f varnishgather/varnishgather.*.tar.gz" 2>/dev/null

echo "$SERVER: Creating new Varnish Gather Report"
if [ -z $NAME ]; then
	ssh root@$SERVER "cd /root/varnishgather;/root/varnishgather/varnishgather" >> /var/log/varnishgather.log 2>/dev/null
else 
	ssh root@$SERVER "cd /root/varnishgather;/root/varnishgather/varnishgather -n $NAME" >> /var/log/varnishgather.log 2>/dev/null
fi

echo "$SERVER: Copying generated report to current directory"
scp root@$SERVER:/root/varnishgather/varnishgather.*.tar.gz ./ 2>/dev/null

if [[ $COLLECT == "true" ]]; then
	echo "Collect mode; not uploading to Varnish!"
	exit 0
fi

######################UPLOAD REPORT TO SUPPORT###############
echo "--------------------------------------------------------"
echo "Uploading files to Varnish support"
for FILE in $(ls *.tar.gz);do
    curl --data-binary "@$FILE" https://filebin.varnish-software.com/ -H "filename: $FILE" -H "bin: $BIN" >>/var/log/varnishgather.log
	if [ $? -ne 0 ]; then
		echo "Upload of $FILE unsuccessful, exiting!"
		exit 1
	else
		echo "Upload of $FILE successful"
	fi
done
echo "========================================================"
echo "BIN URL:https://filebin.varnish-software.com/$BIN"

exit 0
