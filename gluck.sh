#!/bin/bash
. auth.sh

# Timezone for timestamps in CSV
CSVTZ="+2" 

if [[ -z "$1" || ! -f "$1" ]]; then
    echo "Use: $0 YourLog.csv"
    exit 1
fi
INPUT=$1

APP_SCOPE=""
for scope in blood_glucose nutrition; do
    if [[ -n "${APP_SCOPE}" ]]; then APP_SCOPE="$APP_SCOPE+"; fi
    APP_SCOPE="${APP_SCOPE}https://www.googleapis.com/auth/fitness.$scope.read+"
    APP_SCOPE="${APP_SCOPE}https://www.googleapis.com/auth/fitness.$scope.write"
done
loadsecret
AUTH=$(oauth)

createds() {
	DATASOURCE="raw:com.google.blood_glucose:$_secret_project_number:Gluck"
	#curl -X DELETE -H "Authorization: Bearer $AUTH" https://www.googleapis.com/fitness/v1/users/me/dataSources/$DATASOURCE
	curl -s -H "Authorization: Bearer $AUTH" https://www.googleapis.com/fitness/v1/users/me/dataSources | grep $DATASOURCE > /dev/null 2>&1
	if [[ $? -ne 0 ]]; then
		read -r -d '' DATASOURCE << EOM
{
  "dataStreamId": "$DATASOURCE",
  "dataStreamName": "Gluck",
  "type": "raw",
  "application": {
    "detailsUrl": "https://datacompboy.dev/p/gluck",
    "name": "Gluck",
    "version": "1"
  },
  "dataType": {
    "name": "com.google.blood_glucose"
   }
}
EOM
		curl -s -H "Authorization: Bearer $AUTH" -H "Content-Type: application/json;encoding=utf-8" --data-raw "$DATASOURCE" \
			https://www.googleapis.com/fitness/v1/users/me/dataSources | jq -r ".dataStreamId"
	else
		echo $DATASOURCE
	fi
}

DATASOURCE=$(createds)
echo "Datasource: $DATASOURCE"

formatdataarr() {
    echo $1 | jq -c 'map({"startTimeNanos":.ts,"endTimeNanos":.ts,"dataTypeName":"com.google.blood_glucose","value":[{"fpVal":.v}]})'
}
formatdataline() {
    TSNS=$1
    VAL=$2
    echo '{"startTimeNanos":'$TSNS',"endTimeNanos":'$TSNS',"dataTypeName":"com.google.blood_glucose","value":[{"fpVal":'$VAL'},{},{},{},{}]}'
}

replaceday() {
    DAY=$1
    MINTS=$2
    #POINTS=$(formatdataarr $3)
    POINTS=$3
    MODE="Full"
    DAY0="$(date -d "$DAY 00:00:00 UTC" -u "+%s")000000000"
    DAYE="$(date -d "$DAY 23:59:59 UTC" -u "+%s")999999999"
    if [[ $(( MINTS - DAY0 )) -gt $(( 10 * 60 * 1000 * 1000 * 1000 )) ]]; then
        MODE="Partial"
        DAY0=$MINTS
    fi
    echo "$MODE $DAY: $DAY0..$DAYE..." # $DATA"

    DATA='{"minStartTimeNs":'$DAY0',"maxEndTimeNs":'$DAYE',"dataSourceId":"'$DATASOURCE'","point":'$POINTS'}'
    DATASET="https://www.googleapis.com/fitness/v1/users/me/dataSources/$DATASOURCE/datasets/$DAY0-$DAYE"
	curl -s -X DELETE -H "Authorization: Bearer $AUTH" "$DATASET" | head -n 3
    curl -s -X PATCH -H "Authorization: Bearer $AUTH" -H "Content-Type: application/json;encoding=utf-8"  --data-raw "$DATA" "$DATASET" | head -n 3
}

ODATE=""
while IFS="," read -r _ _ INTS RT VAL _; do
    if [[ $RT == "0" ]]; then
        DATE=$(date -d "$INTS $CSVTZ" -u "+%F")
        TSNS="$(date -d "$INTS $CSVTZ" -u "+%s")000000000"
       
        if [[ "$DATE" != "$ODATE" ]]; then
            if [[ -n "$ODATE" ]]; then
                replaceday $ODATE $MINTS "$DATA]"
            fi
            ODATE=$DATE
            MINTS=$TSNS
            DATA=""
        fi
        if [[ -n "$DATA" ]]; then
            #DATA="$DATA,{\"ts\":$TSNS,\"v\":$VAL}"
            DATA="$DATA,$(formatdataline $TSNS $VAL)"
        else
            DATA="[$(formatdataline $TSNS $VAL)"
        fi
    fi
done < <(tail -n +2 $INPUT)
replaceday $DATE $MINTS "$DATA]"

